import AppKit
import Foundation
import RoTypeCore
import RoTypeXPCProtocol
import Security

@MainActor
final class TranslationCoordinator {
    private struct SessionKey: Hashable {
        let connectionID: UUID
        let sessionID: String
    }

    private struct Plan {
        let direction: DynamicTranslationDirection
        let sourceText: String
    }

    private let backend: any DynamicTextTranslating
    private var latestGenerations: [SessionKey: Int64] = [:]
    private var tasks: [SessionKey: Task<Void, Never>] = [:]
    private var controllerInputGeneration: Int64 = 0

    init(backend: any DynamicTextTranslating = DynamicTranslatorFactory.make()) {
        self.backend = backend
    }

    // Both wire versions share scheduling; only validated v2 requests supply a direction.
    // swiftlint:disable:next function_parameter_count
    func translate(
        connectionID: UUID,
        sessionID: String,
        generation: Int64,
        rawInput: String,
        sourceText: String,
        explicitDirection: DynamicTranslationDirection? = nil,
        withReply reply: @escaping @Sendable (Int64, String?, String?, String?, NSError?) -> Void
    ) {
        guard Self.isValid(sessionID: sessionID, rawInput: rawInput, sourceText: sourceText) else {
            reply(generation, nil, nil, nil, Self.error(code: 1, description: "Invalid translation request."))
            return
        }

        let key = SessionKey(connectionID: connectionID, sessionID: sessionID)
        if let latest = latestGenerations[key], generation <= latest {
            reply(generation, nil, nil, nil, Self.error(code: 2, description: "Stale translation generation."))
            return
        }
        latestGenerations[key] = generation
        tasks.removeValue(forKey: key)?.cancel()

        guard DynamicTranslationPolicy.shouldTranslate(sourceText) else {
            reply(generation, nil, nil, nil, nil)
            return
        }

        let plan = explicitDirection.map { Plan(direction: $0, sourceText: sourceText) }
            ?? Self.plan(sourceText: sourceText)
        tasks[key] = Task { [weak self, backend] in
            defer {
                if self?.latestGenerations[key] == generation { self?.tasks[key] = nil }
            }
            do {
                try await Task.sleep(for: .milliseconds(120))
                try Task.checkCancellation()
                let translated = try await backend.translate(plan.sourceText, direction: plan.direction)
                try Task.checkCancellation()
                guard let self, self.latestGenerations[key] == generation else {
                    reply(generation, nil, nil, nil, Self.error(code: 3, description: "Translation superseded."))
                    return
                }
                reply(generation, plan.direction.rawValue, plan.sourceText, translated, nil)
            } catch is CancellationError {
                reply(generation, nil, nil, nil, Self.error(code: 4, description: "Translation cancelled."))
            } catch {
                reply(generation, nil, nil, nil, error as NSError)
            }
        }
    }

    func cancel(connectionID: UUID, sessionID: String, throughGeneration: Int64) {
        let key = SessionKey(connectionID: connectionID, sessionID: sessionID)
        guard let latest = latestGenerations[key], latest <= throughGeneration else { return }
        tasks.removeValue(forKey: key)?.cancel()
    }

    func removeConnection(_ connectionID: UUID) {
        let keys = latestGenerations.keys.filter { $0.connectionID == connectionID }
        for key in keys {
            tasks.removeValue(forKey: key)?.cancel()
            latestGenerations[key] = nil
        }
    }

    func recordControllerInput() {
        controllerInputGeneration = controllerInputGeneration == Int64.max
            ? 1
            : controllerInputGeneration + 1
    }

    func currentControllerInputGeneration() -> Int64 {
        controllerInputGeneration
    }

    private static func isValid(sessionID: String, rawInput: String, sourceText: String) -> Bool {
        UUID(uuidString: sessionID) != nil
            && rawInput.utf8.count <= RoTypeTranslationXPC.maximumTextLength
            && !rawInput.isEmpty
            && sourceText.utf8.count <= RoTypeTranslationXPC.maximumTextLength
            && !sourceText.isEmpty
    }

    private static func plan(sourceText: String) -> Plan {
        // Legacy v1 compatibility only; v2 supplies an explicit validated direction.
        .init(direction: DynamicTranslationPolicy.direction(for: sourceText) ?? .chineseToEnglish,
              sourceText: sourceText)
    }

    private static func error(code: Int, description: String) -> NSError {
        NSError(
            domain: RoTypeTranslationXPC.errorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

enum TranslationClientRole {
    case inputMethod
    case settingsHelper
}

final class TranslationXPCService: NSObject, RoTypeTranslationXPCProtocol {
    private final class Reply: @unchecked Sendable {
        private let block: (Int64, String?, String?, String?, Error?) -> Void

        init(_ block: @escaping (Int64, String?, String?, String?, Error?) -> Void) {
            self.block = block
        }

        func call(
            _ generation: Int64,
            _ direction: String?,
            _ sourceText: String?,
            _ translatedText: String?,
            _ error: NSError?
        ) {
            block(generation, direction, sourceText, translatedText, error)
        }
    }

    private final class GenerationReply: @unchecked Sendable {
        private let block: (Int64, Error?) -> Void

        init(_ block: @escaping (Int64, Error?) -> Void) {
            self.block = block
        }

        func call(_ generation: Int64, _ error: NSError?) {
            block(generation, error)
        }
    }

    private let connectionID = UUID()
    private let coordinator: TranslationCoordinator
    private let role: TranslationClientRole

    init(coordinator: TranslationCoordinator, role: TranslationClientRole) {
        self.coordinator = coordinator
        self.role = role
        super.init()
    }

    func translate(
        sessionID: String,
        generation: Int64,
        rawInput: String,
        sourceText: String,
        withReply reply: @escaping (Int64, String?, String?, String?, Error?) -> Void
    ) {
        guard role == .inputMethod else {
            reply(generation, nil, nil, nil, Self.authorizationError())
            return
        }
        let reply = Reply(reply)
        Task { @MainActor [connectionID, coordinator] in
            coordinator.translate(
                connectionID: connectionID,
                sessionID: sessionID,
                generation: generation,
                rawInput: rawInput,
                sourceText: sourceText,
                withReply: reply.call
            )
        }
    }

    func translateCandidate(
        sessionID: String,
        generation: Int64,
        request: [String: String],
        withReply reply: @escaping (Int64, String?, String?, String?, Error?) -> Void
    ) {
        guard role == .inputMethod else {
            reply(generation, nil, nil, nil, Self.authorizationError())
            return
        }
        let candidate: CandidateTranslationRequest
        do {
            candidate = try CandidateTranslationRequest(payload: request)
        } catch {
            let unsupported = (error as? CandidateTranslationRequest.ValidationError) == .unsupportedVersion
            reply(generation, nil, nil, nil, NSError(
                domain: RoTypeTranslationXPC.errorDomain, code: unsupported ? 6 : 1,
                userInfo: [NSLocalizedDescriptionKey: unsupported ? "候选翻译协议版本不兼容，请完成升级。" : "候选翻译请求无效。"]
            ))
            return
        }
        guard generation > 0 else {
            reply(generation, nil, nil, nil, NSError(domain: RoTypeTranslationXPC.errorDomain, code: 1))
            return
        }
        let reply = Reply(reply)
        Task { @MainActor [connectionID, coordinator] in
            coordinator.translate(connectionID: connectionID, sessionID: sessionID,
                generation: generation, rawInput: candidate.rawInput, sourceText: candidate.sourceText,
                explicitDirection: candidate.direction, withReply: reply.call)
        }
    }

    func cancel(sessionID: String, throughGeneration: Int64) {
        guard role == .inputMethod else { return }
        Task { @MainActor [connectionID, coordinator] in
            coordinator.cancel(
                connectionID: connectionID,
                sessionID: sessionID,
                throughGeneration: throughGeneration
            )
        }
    }

    func recordControllerInput() {
        guard role == .inputMethod else { return }
        Task { @MainActor [coordinator] in
            coordinator.recordControllerInput()
        }
    }

    func controllerInputGeneration(reply: @escaping (Int64, Error?) -> Void) {
        guard role == .settingsHelper else {
            reply(0, Self.authorizationError())
            return
        }
        let reply = GenerationReply(reply)
        Task { @MainActor [coordinator] in
            reply.call(coordinator.currentControllerInputGeneration(), nil)
        }
    }

    func invalidate() {
        Task { @MainActor [connectionID, coordinator] in
            coordinator.removeConnection(connectionID)
        }
    }
    private static func authorizationError() -> NSError {
        NSError(
            domain: RoTypeTranslationXPC.errorDomain,
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "The XPC operation is not allowed for this client."]
        )
    }
}

final class TranslationXPCListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    typealias ConnectionValidator = (NSXPCConnection) -> TranslationClientRole?

    private let coordinator: TranslationCoordinator
    private let clientRole: ConnectionValidator
    private let idleExitDelay: TimeInterval
    private let lock = NSLock()
    private var connectionCount = 0
    private var idleGeneration: UUID?

    init(
        coordinator: TranslationCoordinator = MainActor.assumeIsolated { TranslationCoordinator() },
        clientRole: @escaping ConnectionValidator = TranslationClientCodeValidator.role,
        idleExitDelay: TimeInterval = ProcessInfo.processInfo.environment[
            "ROTYPE_TRANSLATION_IDLE_TIMEOUT"
        ].flatMap(TimeInterval.init) ?? 30
    ) {
        self.coordinator = coordinator
        self.clientRole = clientRole
        self.idleExitDelay = idleExitDelay
        super.init()
        scheduleIdleExit()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let role = clientRole(connection) else { return false }

        let service = TranslationXPCService(coordinator: coordinator, role: role)
        connection.exportedInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak self, service] in
            service.invalidate()
            self?.connectionClosed()
        }
        connectionInterruptedOrOpened()
        connection.resume()
        return true
    }

    private func connectionInterruptedOrOpened() {
        lock.lock()
        connectionCount += 1
        idleGeneration = nil
        lock.unlock()
    }

    private func connectionClosed() {
        lock.lock()
        connectionCount = max(0, connectionCount - 1)
        guard connectionCount == 0 else {
            lock.unlock()
            return
        }
        let generation = UUID()
        idleGeneration = generation
        lock.unlock()
        scheduleIdleExit(generation: generation)
    }

    private func scheduleIdleExit() {
        lock.lock()
        let generation = UUID()
        idleGeneration = generation
        lock.unlock()
        scheduleIdleExit(generation: generation)
    }

    private func scheduleIdleExit(generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + idleExitDelay) { [weak self] in
            self?.exitIfIdle(generation: generation)
        }
    }

    private func exitIfIdle(generation: UUID) {
        lock.lock()
        let shouldExit = connectionCount == 0 && idleGeneration == generation
        lock.unlock()
        if shouldExit {
            Foundation.exit(EXIT_SUCCESS)
        }
    }
}

private enum TranslationClientCodeValidator {
    static func role(for connection: NSXPCConnection) -> TranslationClientRole? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code,
              let teamID = ownTeamIdentifier() else { return nil }

        if satisfies(code, teamID: teamID, identifier: "im.roarkai.inputmethod.Luoke") {
            return .inputMethod
        }
        if satisfies(code, teamID: teamID, identifier: "im.roarkai.inputmethod.Luoke.helper") {
            return .settingsHelper
        }
        return nil
    }

    private static func satisfies(_ code: SecCode, teamID: String, identifier: String) -> Bool {
        var requirement: SecRequirement?
        let requirementText = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" "
            + "and identifier \"\(identifier)\""
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func ownTeamIdentifier() -> String? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL as CFURL
        var ownCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL, [], &ownCode) == errSecSuccess,
              let ownCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            ownCode,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &information
        ) == errSecSuccess,
              let values = information as? [CFString: Any] else { return nil }
        return values[kSecCodeInfoTeamIdentifier] as? String
    }
}
