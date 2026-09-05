import AppKit

@main
@MainActor
struct PanelTests {
  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
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
