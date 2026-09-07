import AppKit
import SwiftUI
@testable import RoTypeApp

/// Offscreen, read-only native views. No AppDelegate, activation.restore(), recording or typing.
@main @MainActor
struct SettingsPreview {
    static func main() throws {
        precondition(Bundle.main.bundleIdentifier != "im.roarkai.inputmethod.Luoke.helper")
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let domain = "RoType.settings-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "onboarding.completed.keyboard-and-translation")
        let settings = RoTypeSettings(defaults: defaults, probe: { .ready })
        settings.setTranslationReady(true)
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for (index, section) in SettingsSection.allCases.enumerated() {
                let content = SettingsHomeView(settings: settings, selection: section)
                    .modifier(SettingsSurface())
                    .environment(\.colorScheme, dark ? .dark : .light)
                let path = output.appendingPathComponent("\(dark ? "dark" : "light")-\(index)-\(section.rawValue).png")
                try save(content, size: NSSize(width: 880, height: 660), to: path)
            }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        for (name, state) in [("granted", VoicePermissions.Authorization.granted), ("denied", .denied)] {
            let pane = VoicePermissionsPane(readSnapshot: { .init(microphone: state, accessibility: state) })
                .padding(24).modifier(SettingsSurface()).environment(\.colorScheme, .light)
            try save(pane, size: NSSize(width: 660, height: 370),
                     to: output.appendingPathComponent("permissions-\(name)-fixture.png"))
        }
        precondition(!VoiceInputController.shared.activation.isObserving)
        precondition(!VoiceInputController.shared.enabled)
        VoiceInputController.shared.shutdown()
    }

    private static func save<Content: View>(_ content: Content, size: NSSize, to path: URL) throws {
        let bounds = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        let view = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        view.sizingOptions = []
        window.contentView = view
        view.frame = bounds
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
        window.contentView = nil
    }
}
