import AppKit
import Testing
@testable import RoTypeApp

@Test @MainActor func voiceHUDUsesCompactNonactivatingLayout() {
    _ = NSApplication.shared
    let hud = VoiceHUD()
    for state in [VoiceHUD.State.recording, .preparing, .processing, .success("已填入 · 未发送")] {
        hud.render(state)
        #expect(hud.presentationSize == NSSize(width: 188, height: 36))
        #expect(!hud.acceptsKeyboardFocus)
    }
}

@Test @MainActor func voiceHUDOnlyExpandsDetailsOnRequest() {
    _ = NSApplication.shared
    let hud = VoiceHUD()
    let text = String(repeating: "完整识别文字。", count: 500)
    hud.render(.result(text, reason: "输入目标已变化"))
    #expect(hud.presentationSize == NSSize(width: 240, height: 36))
    #expect(hud.state.title == "未能填入")
    #expect(hud.state.detail == "输入目标已变化\n\n" + text)
    hud.toggleDetails()
    #expect(hud.expanded)
    #expect(hud.presentationSize == NSSize(width: 288, height: 180))
    hud.render(.recording)
    #expect(!hud.expanded)
    #expect(hud.state.detail == nil)
    hud.toggleDetails()
    #expect(!hud.expanded)
}

@Test @MainActor func voiceHUDMeterRequiresRealSamples() {
    let waveform = VoiceHUDWaveform()
    #expect(waveform.levels.allSatisfy { $0 == 0 })
    waveform.append(decibels: -10)
    #expect(waveform.levels.last == 1)
    for _ in 0..<9 { waveform.append(decibels: -80) }
    #expect(waveform.levels.allSatisfy { $0 == 0 })
    waveform.append(decibels: .nan)
    #expect(waveform.levels.last == 0)
    waveform.reset()
    #expect(waveform.levels.count == 9)
}
