import Foundation
import Testing
@testable import RoTypeCore

@Test func coldModelKeepsFirstRecordingUntilReady() {
    var queue = VoicePendingTranscription()
    let id = UUID()
    let audio = URL(fileURLWithPath: "/tmp/test-recording.caf")
    queue.enqueue(id: id, audio: audio)
    let waiting = queue.take(ready: false)
    #expect(waiting == nil)
    let ready = queue.take(ready: true)
    #expect(ready?.id == id)
    #expect(ready?.audio == audio)
    let duplicate = queue.take(ready: true)
    #expect(duplicate == nil)
}

@Test func cancellingWhileModelLoadsCannotReviveOldRecording() {
    var queue = VoicePendingTranscription()
    queue.enqueue(id: UUID(), audio: URL(fileURLWithPath: "/tmp/cancelled.caf"))
    queue.cancel()
    let late = queue.take(ready: true)
    #expect(late == nil)
}
