import AppKit
import SwiftUI

struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(CossStyle.muted)
                .frame(width: 22, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(CossStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
            Text(title).font(.system(size: 23, weight: .semibold)).tracking(-0.4)
            Text(detail).font(.system(size: 13)).foregroundStyle(CossStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CossStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(CossStyle.border, lineWidth: 1))
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
        window.setContentSize(NSSize(width: 880, height: 660))
        window.minSize = NSSize(width: 760, height: 560)
        window.title = "洛克输入法设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.settings = settings
        window.delegate = self
    }
}
