import AppKit

@MainActor
final class StatusPanel {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center

        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 220, height: 52))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        label.frame = visualEffect.bounds.insetBy(dx: 14, dy: 12)
        visualEffect.addSubview(label)

        panel = NSPanel(
            contentRect: visualEffect.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = visualEffect
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ text: String) {
        label.stringValue = text
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - frame.width / 2,
            y: screen.visibleFrame.maxY - frame.height - 32
        ))
        panel.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0) {
        if delay == 0 {
            panel.orderOut(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak panel] in
                panel?.orderOut(nil)
            }
        }
    }
}
