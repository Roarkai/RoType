import AppKit
import Foundation
import RoTypeVoiceCore

@MainActor
final class DynamicTranslationService {
    typealias StatusHandler = @MainActor (String) -> Void

    private struct TranslationPlan {
        let direction: DynamicTranslationResponse.Direction
        let sourceText: String
    }

    private let directory: URL
    private let backend: any DynamicTextTranslating
    private let statusHandler: StatusHandler
    private var timer: Timer?
    private var currentRequests: [String: DynamicTranslationRequest] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var lastReportedError: String?
    private var reportedMissingPostEventAccess = false

    init(
        directory: URL? = nil,
        backend: any DynamicTextTranslating = DynamicTranslatorFactory.make(),
        statusHandler: @escaping StatusHandler
    ) {
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/RoType/TranslationBridge", isDirectory: true)
        self.backend = backend
        self.statusHandler = statusHandler
    }

    func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanRequests() }
        }
        scanRequests()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        for task in refreshTasks.values { task.cancel() }
        refreshTasks.removeAll()
    }

    private func scanRequests() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in files where url.lastPathComponent.hasPrefix("request-") && url.pathExtension == "txt" {
            guard
                let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                DynamicTranslationBridgePolicy.shouldProcessRequest(modifiedAt: modifiedAt),
                let data = try? Data(contentsOf: url),
                let request = DynamicTranslationRequest(data: data)
            else { continue }
            let sessionID = String(url.deletingPathExtension().lastPathComponent.dropFirst("request-".count))
            accept(request, sessionID: sessionID)
        }
    }

    private func accept(_ request: DynamicTranslationRequest, sessionID: String) {
        guard currentRequests[sessionID] != request else { return }
        currentRequests[sessionID] = request
        tasks[sessionID]?.cancel()
        refreshTasks[sessionID]?.cancel()
        tasks[sessionID] = Task { [weak self, backend] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                try Task.checkCancellation()
                let plan = Self.plan(for: request)
                let translated = try await backend.translate(plan.sourceText, direction: plan.direction)
                try Task.checkCancellation()
                guard !translated.isEmpty else { return }
                self?.complete(
                    request: request,
                    sessionID: sessionID,
                    direction: plan.direction,
                    sourceText: plan.sourceText,
                    translatedText: translated
                )
            } catch is CancellationError {
                return
            } catch {
                self?.report(error)
            }
        }
    }

    private static func plan(for request: DynamicTranslationRequest) -> TranslationPlan {
        let englishInput = request.rawInput.replacingOccurrences(of: "'", with: " ")
        if isASCII(request.topCandidate) || isLikelyEnglish(englishInput) {
            return .init(direction: .englishToChinese, sourceText: englishInput)
        }
        return .init(direction: .chineseToEnglish, sourceText: request.topCandidate)
    }

    private static func isASCII(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy(\.isASCII)
    }

    private static func isLikelyEnglish(_ value: String) -> Bool {
        let words = value.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.allSatisfy({ $0.allSatisfy(\.isLetter) }) else { return false }
        return words.allSatisfy { word in
            let range = NSRange(location: 0, length: word.utf16.count)
            return NSSpellChecker.shared.checkSpelling(
                of: word,
                startingAt: 0,
                language: "en_US",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            ).location == NSNotFound && range.length > 1
        }
    }

    private func complete(
        request: DynamicTranslationRequest,
        sessionID: String,
        direction: DynamicTranslationResponse.Direction,
        sourceText: String,
        translatedText: String
    ) {
        guard currentRequests[sessionID] == request else { return }
        let response = DynamicTranslationResponse(
            request: request,
            direction: direction,
            sourceText: sourceText,
            translatedText: translatedText
        )
        let url = directory.appendingPathComponent("response-\(sessionID).txt")
        do {
            try response.encoded().write(to: url, options: .atomic)
            scheduleRefreshEvents(for: request, sessionID: sessionID)
            lastReportedError = nil
        } catch {
            report(error)
        }
    }

    private func scheduleRefreshEvents(
        for request: DynamicTranslationRequest,
        sessionID: String
    ) {
        refreshTasks[sessionID]?.cancel()
        refreshTasks[sessionID] = Task { [weak self] in
            for delay in [0, 120, 360] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard
                    !Task.isCancelled,
                    self?.currentRequests[sessionID] == request
                else { return }
                self?.postRefreshEvent()
            }
        }
    }

    private func postRefreshEvent() {
        let keyCode: CGKeyCode = 79 // F18; consumed by rotype_dynamic_refresh.lua.
        guard CGPreflightPostEventAccess() else {
            if !reportedMissingPostEventAccess {
                reportedMissingPostEventAccess = true
                statusHandler("请在系统设置的辅助功能中重新添加 RoType Voice。")
            }
            return
        }
        reportedMissingPostEventAccess = false
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func report(_ error: Error) {
        let message = error.localizedDescription
        guard message != lastReportedError else { return }
        lastReportedError = message
        statusHandler(message)
    }
}
