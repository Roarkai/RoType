import Testing
@testable import RoTypeVoiceCore

@Test func chunksLongTextWithoutChangingIt() {
    let input = "你好 hello 👨‍👩‍👧‍👦，这是一个双语输入测试。"
    let chunks = TextChunker.chunks(input, maximumUTF16Length: 8)

    #expect(chunks.joined() == input)
    #expect(chunks.contains { $0.contains("👨‍👩‍👧‍👦") })
    // One composed character may itself exceed the requested chunk size.
    #expect(chunks.allSatisfy { $0.utf16.count <= 11 })
}

@Test func leavesShortTextInOneChunk() {
    #expect(TextChunker.chunks("你好") == ["你好"])
}

@Test func emptyTextProducesNoEvents() {
    #expect(TextChunker.chunks("").isEmpty)
}
