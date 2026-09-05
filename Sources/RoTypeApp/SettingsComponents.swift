import AppKit
import SwiftUI

struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 28)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

struct PaneTitle: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary)
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
final class RoTypeSettingsWindowController: NSWindowController, NSWindowDelegate {
    private var settings: RoTypeSettings?

    func windowWillClose(_ notification: Notification) {
        if settings?.onboardingCompleted == false { settings?.setupDeferred = true }
    }

    convenience init(settings: RoTypeSettings) {
        let controller = NSHostingController(rootView: RoTypeSettingsRootView(settings: settings))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 760, height: 580))
        window.minSize = NSSize(width: 680, height: 520)
        window.title = "洛克输入法设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.settings = settings
        window.delegate = self
    }
}
