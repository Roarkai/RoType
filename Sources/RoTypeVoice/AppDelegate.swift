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
    private var statusItem: NSStatusItem?
    private var translationSetupWindow: NSWindowController?
    private lazy var translationService = DynamicTranslationService { [weak self] message in
        self?.statusPanel.show(message)
        self?.statusPanel.hide(after: 3)
    }
    private var isStartingRecording = false
    private var isRecording = false
    private var releaseRequestedWhileStarting = false

    private enum StatusIcon {
        static let idle = "waveform"
        static let recording = "waveform.circle.fill"
        static let processing = "ellipsis.circle"
        static let success = "checkmark.circle.fill"
        static let failure = "exclamationmark.triangle.fill"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
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

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.stop()
        translationService.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "RoType Voice"
        }
        statusItem = item
        setStatusIcon(StatusIcon.idle, description: "RoType Voice 已就绪")

        let menu = NSMenu()
        let hint = NSMenuItem(title: "按住右 Option 说话", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let translationSetup = NSMenuItem(
            title: "准备中英翻译语言包…",
            action: #selector(openTranslationSetup),
            keyEquivalent: ""
        )
        translationSetup.target = self
        menu.addItem(translationSetup)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 RoType Voice", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
    }

    private func setStatusIcon(_ symbolName: String, description: String) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: StatusIcon.idle, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    private func restoreIdleIcon(after seconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !self.isStartingRecording, !self.isRecording else { return }
            self.setStatusIcon(StatusIcon.idle, description: "RoType Voice 已就绪")
        }
    }

    private func beginRecording() {
        guard !isStartingRecording, !isRecording else { return }
        isStartingRecording = true
        releaseRequestedWhileStarting = false
        statusPanel.show("● 录音中")
        setStatusIcon(StatusIcon.recording, description: "RoType Voice 正在录音")

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
                setStatusIcon(StatusIcon.failure, description: "RoType Voice 录音失败")
                restoreIdleIcon(after: 3)
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
                setStatusIcon(StatusIcon.processing, description: "RoType Voice 正在转写")
                defer { try? FileManager.default.removeItem(at: url) }

                let text = try await transcriber.transcribe(audioAt: url)
                guard !text.isEmpty else {
                    statusPanel.show("没有识别到语音")
                    statusPanel.hide(after: 1.5)
                    setStatusIcon(StatusIcon.idle, description: "RoType Voice 已就绪")
                    return
                }

                try inserter.insert(text)
                statusPanel.show("已插入")
                statusPanel.hide(after: 0.8)
                setStatusIcon(StatusIcon.success, description: "RoType Voice 已插入文字")
                restoreIdleIcon(after: 0.8)
            } catch {
                setStatusIcon(StatusIcon.failure, description: "RoType Voice 处理失败")
                restoreIdleIcon(after: 3)
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        statusPanel.show(error.localizedDescription)
        statusPanel.hide(after: 3)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
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
