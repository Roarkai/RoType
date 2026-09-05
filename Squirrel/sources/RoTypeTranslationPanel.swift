import AppKit

// A compact action row, not a virtual Rime candidate or an activating window.
final class RoTypeTranslationPanel: NSPanel {
  private let shortcutLabel = NSTextField(labelWithString: "")
  private let action = NSButton(title: "", target: nil, action: nil)
  private let surface = NSView()
  var onActivate: (() -> Void)?

  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 34),
               styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    surface.wantsLayer = true
    surface.layer?.cornerRadius = 9
    surface.layer?.masksToBounds = true
    surface.layer?.borderWidth = 0.5
    contentView = surface
    for label in [shortcutLabel] {
      label.alignment = .center
      label.font = .systemFont(ofSize: 10.5, weight: .medium)
      label.wantsLayer = true
      label.layer?.cornerRadius = 5
      surface.addSubview(label)
    }
    action.isBordered = false
    action.alignment = .left
    action.font = .systemFont(ofSize: 15)
    action.cell?.wraps = true
    action.cell?.lineBreakMode = .byWordWrapping
    action.target = self
    action.action = #selector(activate)
    surface.addSubview(action)
    setAccessibilityLabel("候选翻译区")
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func show(_ state: RoTypeCandidateTranslationSession, beside parent: NSPanel) {
    guard let ticket = state.ticket, parent.isVisible else { orderOut(nil); return }
    appearance = parent.appearance
    level = parent.level
    let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let ink = NSColor(white: dark ? 0.94 : 0.20, alpha: 1)
    let muted = NSColor(white: dark ? 0.66 : 0.43, alpha: 1)
    surface.layer?.backgroundColor = NSColor(white: dark ? 0.14 : 1, alpha: 1).cgColor
    surface.layer?.borderColor = NSColor(white: dark ? 1 : 0, alpha: 0.10).cgColor
    let scope = ticket.snapshot.scope == "whole" ? "整句" : "当前词"
    shortcutLabel.stringValue = "Tab"
    shortcutLabel.isHidden = state.commit == nil && !state.canRetry
    shortcutLabel.textColor = muted
    shortcutLabel.layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: 0.045).cgColor
    let failureText = (state.failure ?? "暂不可用") + (state.canRetry ? "，按 Tab 重试" : "")
    let text = state.commit?.text ?? (state.isLoading ? "正在翻译…" : failureText)
    action.attributedTitle = NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 15),
      .foregroundColor: state.commit == nil ? muted : ink
    ])
    action.isEnabled = state.commit != nil || state.canRetry
    action.toolTip = state.commit?.text ?? state.failure
    action.setAccessibilityLabel("\(scope)翻译：\(text)")
    action.setAccessibilityHelp(state.canRetry ? "点击或按 Tab 重试，不会提交旧译文" : "翻译完成后点击译文或按 Tab 上屏")
    let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
    let width = min(max(parent.frame.width, 300), screen.width)
    let textWidth = width - 56
    let measured = (text as NSString).boundingRect(
      with: NSSize(width: textWidth, height: 100), options: [.usesLineFragmentOrigin],
      attributes: [.font: NSFont.systemFont(ofSize: 15)])
    let height: CGFloat = measured.height > 23 ? 54 : 34
    var origin = NSPoint(x: parent.frame.minX, y: parent.frame.minY - height - 3)
    if origin.y < screen.minY { origin.y = parent.frame.maxY + 3 }
    origin.x = max(screen.minX, min(origin.x, screen.maxX - width))
    origin.y = max(screen.minY, min(origin.y, screen.maxY - height))
    setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    action.frame = NSRect(x: 12, y: 3, width: textWidth, height: height - 6)
    shortcutLabel.frame = NSRect(x: width - 34, y: (height - 18) / 2 - 3, width: 26, height: 18)
    orderFront(nil)
  }

  @objc private func activate() { onActivate?() }
}
