import AppKit

@main
@MainActor
struct PanelTests {
  static func main() {
    if RoTypeInputModePanel.showsLegacyStatus(for: "ascii_mode") {
      print("FAIL: ascii_mode must not show both legacy text and the mode badge")
      exit(1)
    }
    for option in ["full_shape", "ascii_punct", "simplification"] {
      precondition(RoTypeInputModePanel.showsLegacyStatus(for: option))
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var forgotten = 0
    let menu = RoTypeCandidateLearningMenu.make(candidate: "事件", canForget: true) { forgotten += 1 }
    let item = menu.item(at: 0)!
    precondition(item.title == "忘记「事件」的学习记录" && item.isEnabled)
    precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
    precondition(forgotten == 1)
    let disabled = RoTypeCandidateLearningMenu.make(candidate: "时间", canForget: false) { forgotten += 1 }
    let disabledItem = disabled.item(at: 0)!
    precondition(!disabledItem.isEnabled)
    _ = NSApp.sendAction(disabledItem.action!, to: disabledItem.target, from: disabledItem)
    precondition(forgotten == 1, "factory-only candidates cannot invoke forgetting")
    guard let screen = NSScreen.main else {
      print("SKIP: input-mode panel requires a GUI session")
      return
    }
    let panel = RoTypeInputModePanel()
    let visible = screen.visibleFrame
    let caret = NSRect(x: visible.maxX - 1, y: visible.minY + 1, width: 1, height: 18)
    let keyWindow = NSApp.keyWindow
    panel.show(ascii: false, caret: caret)
    precondition(panel.isVisible && !panel.canBecomeKey && !panel.canBecomeMain)
    precondition(panel.ignoresMouseEvents && NSApp.keyWindow === keyWindow)
    precondition(visible.contains(panel.frame), "badge must stay inside the screen")
    savePreview(panel, name: "zh-native")
    RunLoop.current.run(until: Date().addingTimeInterval(0.7))
    panel.show(ascii: true, caret: caret)
    savePreview(panel, name: "en-native")
    RunLoop.current.run(until: Date().addingTimeInterval(0.55))
    precondition(panel.isVisible, "an old dismissal must not hide the new mode")
    RunLoop.current.run(until: Date().addingTimeInterval(0.65))
    precondition(!panel.isVisible, "badge must dismiss automatically")
    panel.show(ascii: false, caret: .zero)
    precondition(!panel.isVisible, "invalid caret must not create a stray badge")
    print("Input mode badge: nonactivating, screen bounds, superseded timer and dismissal passed")
  }

  private static func savePreview(_ panel: NSPanel, name: String) {
    guard CommandLine.arguments.count == 2, let view = panel.contentView,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    precondition(bitmap.hasAlpha)
    let destination = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png")
    try! bitmap.representation(using: .png, properties: [:])!.write(to: destination)
  }
}
