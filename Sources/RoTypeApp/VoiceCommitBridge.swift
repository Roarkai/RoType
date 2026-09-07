import Foundation
import RoTypeXPCProtocol

@MainActor
protocol VoiceCommitTransport: AnyObject {
    func capture(applicationPID: Int32) async -> VoiceCommitBridge.Capture?
    func commit(ticket: String, text: String) async -> Bool
    func cancel(ticket: String)
}

@MainActor
final class VoiceCommitBridge: VoiceCommitTransport {
    struct Capture: Sendable {
        let ticket: String
        let applicationID: String
    }
    private final class Endpoint: @unchecked Sendable {
        let value: NSXPCListenerEndpoint
        init(_ value: NSXPCListenerEndpoint) { self.value = value }
    }
    @MainActor
    private final class Pending<Value: Sendable> {
        private var continuation: CheckedContinuation<Value?, Never>?
        private var timeout: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<Value?, Never>) {
            self.continuation = continuation
            timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                finish(nil)
            }
        }
        func finish(_ value: Value?) {
            let current = continuation
            continuation = nil
            timeout?.cancel()
            timeout = nil
            current?.resume(returning: value)
        }
    }

    private var connection: NSXPCConnection?

    func capture(applicationPID: Int32) async -> Capture? {
        guard let connection = await connect() else { return nil }
        return await withCheckedContinuation { continuation in
            let pending = Pending<Capture>(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                Task { @MainActor in pending.finish(nil) }
            } as? RoTypeDictationXPCProtocol
            guard let proxy else { pending.finish(nil); return }
            proxy.capture(applicationPID: applicationPID) { ticket, applicationID in
                let value = ticket.flatMap { ticket in
                    applicationID.map { Capture(ticket: ticket, applicationID: $0) }
                }
                Task { @MainActor in pending.finish(value) }
            }
        }
    }

    func commit(ticket: String, text: String) async -> Bool {
        guard let connection else { return false }
        let result: Bool? = await withCheckedContinuation { continuation in
            let pending = Pending<Bool>(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                Task { @MainActor in pending.finish(nil) }
            } as? RoTypeDictationXPCProtocol
            guard let proxy else { pending.finish(nil); return }
            proxy.commit(ticket: ticket, text: text, deadline: ProcessInfo.processInfo.systemUptime + 1) { accepted in
                Task { @MainActor in pending.finish(accepted) }
            }
        }
        return result == true
    }

    func cancel(ticket: String) {
        let proxy = connection?.remoteObjectProxyWithErrorHandler { _ in } as? RoTypeDictationXPCProtocol
        proxy?.cancel(ticket: ticket)
    }

    private func connect() async -> NSXPCConnection? {
        if let connection { return connection }
        let registry = NSXPCConnection(machServiceName: ROTYPE_TRANSLATION_SERVICE_NAME)
        registry.setCodeSigningRequirement(Self.requirement("im.roarkai.inputmethod.Luoke.translation"))
        registry.remoteObjectInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
        registry.resume()
        defer { registry.invalidate() }
        let endpoint: Endpoint? = await withCheckedContinuation { continuation in
            let pending = Pending<Endpoint>(continuation)
            let proxy = registry.remoteObjectProxyWithErrorHandler { _ in
                Task { @MainActor in pending.finish(nil) }
            } as? RoTypeTranslationXPCProtocol
            guard let proxy else { pending.finish(nil); return }
            proxy.dictationEndpoint? { endpoint in
                let wrapped = endpoint.map(Endpoint.init)
                Task { @MainActor in pending.finish(wrapped) }
            }
        }
        guard let endpoint else { return nil }
        let direct = NSXPCConnection(listenerEndpoint: endpoint.value)
        direct.setCodeSigningRequirement(Self.requirement("im.roarkai.inputmethod.Luoke"))
        direct.remoteObjectInterface = NSXPCInterface(with: RoTypeDictationXPCProtocol.self)
        direct.interruptionHandler = { [weak self, weak direct] in
            Task { @MainActor in
                if self?.connection === direct { self?.connection = nil }
            }
        }
        direct.invalidationHandler = direct.interruptionHandler
        connection = direct
        direct.resume()
        return direct
    }

    private static func requirement(_ identifier: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"DF7J2VBQD8\" and identifier \"\(identifier)\""
    }
}
