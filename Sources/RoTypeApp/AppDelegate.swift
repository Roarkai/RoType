import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = RoTypeSettings()
    private var settingsWindow: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateExistingInstanceIfNeeded() {
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showSettingsRequested(_:)),
            name: Notification.Name("im.roarkai.inputmethod.Luoke.show-settings"),
            object: nil
        )

        VoiceInputController.shared.restore()

        if CommandLine.arguments.contains("--show-settings") {
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        VoiceInputController.shared.shutdown()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "im.roarkai.inputmethod.Luoke.helper"
        ).first(where: { $0.processIdentifier != currentPID }) else {
            return false
        }
        existing.activate()
        return true
    }

    @objc private func showSettingsRequested(_ notification: Notification) {
        openSettings()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = RoTypeSettingsWindowController(settings: settings)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.center()
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
}
