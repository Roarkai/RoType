import Foundation
import Testing
@testable import RoTypeCore

@Test func voiceResultIsOwnedAndSingleUse() throws {
    var session = VoiceSession()
    let started = session.begin()
    let id = try #require(started)
    #expect(session.begin() == nil)
    #expect(session.takeResult(id: id) == nil)
    #expect(session.stop() == id)
    #expect(session.stop() == nil)
    #expect(session.takeResult(id: UUID()) == nil)
    #expect(session.takeResult(id: id) == true)
    #expect(session.takeResult(id: id) == nil)
}

@Test func cancelledVoiceCannotWriteIntoNextSession() throws {
    var session = VoiceSession()
    let started = session.begin()
    let old = try #require(started)
    _ = session.stop()
    session.cancel()
    let restarted = session.begin()
    let current = try #require(restarted)
    _ = session.stop()
    #expect(session.takeResult(id: old) == nil)
    #expect(session.takeResult(id: current) == true)
}

@Test func targetInvalidationIsStickyUntilNextRecording() throws {
    var session = VoiceSession()
    let started = session.begin()
    let id = try #require(started)
    session.invalidateTarget()
    _ = session.stop()
    #expect(session.takeResult(id: id) == false)
    let restarted = session.begin()
    let next = try #require(restarted)
    _ = session.stop()
    #expect(session.takeResult(id: next) == true)
}

@Test(arguments: [Int64(0), Int64(63)])
func fnWithoutReliableKeycodeStillReleases(key: Int64) {
    var gesture = VoiceFnGesture()
    #expect(gesture.flags(fn: true, key: key, otherModifiers: false, allowed: true).action == .press)
    #expect(gesture.flags(fn: false, key: key, otherModifiers: false, allowed: true).action == .release)
    #expect(!gesture.held)
}

@Test func fnDoesNotStealOtherSourcesOrModifierChords() {
    var gesture = VoiceFnGesture()
    #expect(!gesture.flags(fn: true, key: 63, otherModifiers: false, allowed: false).consume)
    #expect(!gesture.flags(fn: false, key: 63, otherModifiers: false, allowed: false).consume)
    #expect(gesture.flags(fn: true, key: 63, otherModifiers: true, allowed: true).action == .none)
    gesture.reset()
    _ = gesture.flags(fn: true, key: 63, otherModifiers: false, allowed: true)
    let shiftWithMissingKeycode = gesture.flags(fn: true, key: 0, otherModifiers: true, allowed: true)
    #expect(shiftWithMissingKeycode.action == .cancel)
    #expect(!shiftWithMissingKeycode.consume)
    #expect(gesture.flags(fn: false, key: 63, otherModifiers: false, allowed: true).action == .release)
}

@Test func duplicateFnFlagsDoNotRestartOrCancelRecording() {
    var gesture = VoiceFnGesture()
    _ = gesture.flags(fn: true, key: 63, otherModifiers: false, allowed: true)
    let duplicate = gesture.flags(fn: true, key: 63, otherModifiers: false, allowed: true)
    #expect(duplicate.action == .none)
    #expect(duplicate.consume)
    gesture.reset()
    #expect(gesture.flags(fn: false, key: 63, otherModifiers: false, allowed: true).action == .none)
}

@Test func voiceDoesNotExecuteTerminalInputOrInsertControlCharacters() {
    #expect(VoiceInsertionPolicy.allowsAutomaticInsertion(text: "你好", applicationID: "com.apple.TextEdit"))
    for text in ["你好\n", "你好\r", "你好\t", "\u{001b}[A", "第一行\u{2028}第二行"] {
        #expect(!VoiceInsertionPolicy.allowsAutomaticInsertion(text: text, applicationID: "com.apple.TextEdit"))
    }
    for app in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"] {
        #expect(VoiceInsertionPolicy.allowsAutomaticInsertion(text: "echo hello", applicationID: app))
        #expect(!VoiceInsertionPolicy.allowsAutomaticInsertion(text: "echo hello\n", applicationID: app))
        #expect(!VoiceInsertionPolicy.allowsAutomaticInsertion(text: "\u{001b}[A", applicationID: app))
    }
    #expect(!VoiceInsertionPolicy.allowsAutomaticInsertion(text: "你好", applicationID: nil))
}

@Test func voiceModelIntegrityRejectsSameSizeCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("fixture")
    let file = VoiceModelFile("fixture", 3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    try Data("abc".utf8).write(to: url)
    try file.validate(at: url)
    try Data("abd".utf8).write(to: url)
    #expect(throws: (any Error).self) { try file.validate(at: url) }
    try Data("a".utf8).write(to: url)
    #expect(throws: (any Error).self) { try file.validate(at: url) }
    let link = directory.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    #expect(throws: (any Error).self) { try file.validate(at: link) }
}
