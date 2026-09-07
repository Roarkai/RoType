import Foundation
import Testing
@testable import RoTypeCore

private func context(_ activation: UUID, selection: Int = 0, pid: Int32 = 42) -> VoiceCommitTicket.Context {
    VoiceCommitTicket.Context(activation: activation, applicationPID: pid,
                              selection: NSRange(location: selection, length: 0))
}

@Test func nativeVoiceCommitIsSingleUse() {
    var ticket = VoiceCommitTicket()
    let target = context(UUID())
    let token = ticket.capture(target, now: 10)
    let inserted = ticket.consume(token, context: target, now: 20)
    let repeated = ticket.consume(token, context: target, now: 20)
    #expect(inserted)
    #expect(!repeated)
}

@Test func nativeVoiceCommitRejectsChangedInputContexts() {
    let activation = UUID()
    let original = context(activation)
    for changed in [context(UUID()), context(activation, selection: 1), context(activation, pid: 43)] {
        var ticket = VoiceCommitTicket()
        let token = ticket.capture(original, now: 0)
        let changedTarget = ticket.consume(token, context: changed, now: 1)
        let restoredTarget = ticket.consume(token, context: original, now: 2)
        #expect(!changedTarget)
        #expect(!restoredTarget)
    }
}

@Test func nativeVoiceCommitRejectsCancelledExpiredAndSupersededRequests() {
    var ticket = VoiceCommitTicket()
    let target = context(UUID())
    let cancelled = ticket.capture(target, now: 0)
    ticket.cancel()
    let cancelledResult = ticket.consume(cancelled, context: target, now: 1)
    #expect(!cancelledResult)
    let expired = ticket.capture(target, now: 0)
    let expiredResult = ticket.consume(expired, context: target, now: 121)
    #expect(!expiredResult)
    let old = ticket.capture(target, now: 0)
    let current = ticket.capture(target, now: 1)
    ticket.cancel(old)
    let oldResult = ticket.consume(old, context: target, now: 2)
    let currentResult = ticket.consume(current, context: target, now: 2)
    #expect(!oldResult)
    #expect(currentResult)
}

@Test func delayedNativeCommitCannotInsertAfterTheCallerTimeout() {
    var ticket = VoiceCommitTicket()
    let target = context(UUID())
    let token = ticket.capture(target, now: 0)
    let late = ticket.consume(token, context: target, now: 12, deadline: 11)
    let retried = ticket.consume(token, context: target, now: 12, deadline: 13)
    #expect(!late)
    #expect(!retried)
}

@Test func holdingFnDoesNotEndRecordingAtPointThreeSeconds() {
    var gesture = VoiceFnGesture()
    #expect(gesture.flags(fn: true, key: 63, otherModifiers: false, allowed: true).action == .press)
    for seconds in [0.1, 0.3, 1, 10, 58] {
        #expect(!gesture.shouldFinishRecording(elapsed: seconds, recorderIsRunning: true))
    }
    #expect(gesture.flags(fn: true, key: 0, otherModifiers: false, allowed: true).action == .none)
    #expect(!gesture.shouldFinishRecording(elapsed: 12, recorderIsRunning: true))
    #expect(gesture.flags(fn: false, key: 0, otherModifiers: false, allowed: true).action == .release)
    #expect(gesture.shouldFinishRecording(elapsed: 12.1, recorderIsRunning: true))
}

@Test func recordingStillStopsOnDeviceFailureOrSafetyLimit() {
    var gesture = VoiceFnGesture()
    _ = gesture.flags(fn: true, key: 63, otherModifiers: false, allowed: true)
    #expect(gesture.shouldFinishRecording(elapsed: 1, recorderIsRunning: false))
    #expect(gesture.shouldFinishRecording(elapsed: 59, recorderIsRunning: true))
    gesture.reset()
    #expect(gesture.shouldFinishRecording(elapsed: 1, recorderIsRunning: true))
}
