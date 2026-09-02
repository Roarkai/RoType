import AppKit
import RoTypeVoiceCore
@preconcurrency import Translation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = AudioRecorder()
    private let transcriber = WhisperTranscriber()
    private let inserter = TextInserter()
    private let hotKey = HotKeyMonitor()
    private let statusPanel = StatusPanel()
    private var translationSetupWindow: NSWindowController?
    private lazy var translationService = DynamicTranslationService { [weak self] message in
        self?.statusPanel.show(message)
        self?.statusPanel.hide(after: 3)
    }
    private var isStartingRecording = false
    private var isRecording = false
    private var releaseRequestedWhileStarting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = inserter.requestAccessibilityIfNeeded()

        hotKey.onPressed = { [weak self] in self?.beginRecording() }
        hotKey.onReleased = { [weak self] in self?.finishRecording() }

        do {
            try translationService.start()
        } catch {
            show(error)
        }

        do {
            try hotKey.start()
        } catch {
            show(error)
        }

        Task { await openTranslationSetupIfNeeded() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "rotype" && $0.host == "settings" }) else { return }
        openTranslationSetup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.stop()
        translationService.stop()
    }

    private func beginRecording() {
        guard !isStartingRecording, !isRecording else { return }
        isStartingRecording = true
        releaseRequestedWhileStarting = false
        statusPanel.show("● 录音中")

        Task {
            do {
                try await recorder.start()
                isStartingRecording = false
                isRecording = true
                if releaseRequestedWhileStarting {
                    finishRecording()
                }
            } catch {
                isStartingRecording = false
                isRecording = false
                show(error)
            }
        }
    }

    private func finishRecording() {
        if isStartingRecording {
            releaseRequestedWhileStarting = true
            return
        }
        guard isRecording else { return }
        isRecording = false

        Task {
            do {
                let url = try recorder.stop()
                statusPanel.show("转写中…")
                defer { try? FileManager.default.removeItem(at: url) }

                let text = try await transcriber.transcribe(audioAt: url)
                guard !text.isEmpty else {
                    statusPanel.show("没有识别到语音")
                    statusPanel.hide(after: 1.5)
                    return
                }

                try inserter.insert(text)
                statusPanel.show("已插入")
                statusPanel.hide(after: 0.8)
            } catch {
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        statusPanel.show(error.localizedDescription)
        statusPanel.hide(after: 3)
    }

    @objc private func openTranslationSetup() {
        guard #available(macOS 15.0, *) else {
            statusPanel.show("Apple 本地翻译需要 macOS 15 或更高版本。")
            statusPanel.hide(after: 3)
            return
        }
        if translationSetupWindow == nil {
            translationSetupWindow = TranslationSetupWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        translationSetupWindow?.showWindow(nil)
        translationSetupWindow?.window?.center()
        translationSetupWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func openTranslationSetupIfNeeded() async {
        guard #available(macOS 15.0, *) else { return }
        let chinese = Locale.Language(identifier: "zh-Hans")
        let english = Locale.Language(identifier: "en")
        let status = await LanguageAvailability().status(from: chinese, to: english)
        guard status != .installed else { return }
        openTranslationSetup()
    }
}
