import Testing
@testable import RoTypeCore

@Test func paragraphSeparatorsNeverReachAnInputClientAsReturn() {
    for separator in ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"] {
        let text = VoiceInsertionPolicy.singleLineText("第一段" + separator + "第二段")
        #expect(text == "第一段 第二段")
        #expect(VoiceInsertionPolicy.allowsAutomaticInsertion(text: text, applicationID: "com.mitchellh.ghostty"))
    }
}

@Test func normalizationDoesNotAllowTerminalControlSequences() {
    for text in ["文字\t补全", "\u{001b}[A", "\u{0003}", "\u{0004}"] {
        #expect(!VoiceInsertionPolicy.allowsAutomaticInsertion(
            text: VoiceInsertionPolicy.singleLineText(text), applicationID: "com.apple.Terminal"))
    }
    #expect(!VoiceInsertionPolicy.allowsAutomaticInsertion(text: "文字", applicationID: ""))
}
