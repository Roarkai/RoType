import RoTypeCore
import Testing
@testable import RoTypeApp

@MainActor
private final class NativeDeliveryFixture: VoiceCommitTransport {
    var committed: [String] = []
    func capture(applicationPID: Int32) async -> VoiceCommitBridge.Capture? {
        .init(ticket: "fixture-ticket", applicationID: "com.mitchellh.ghostty")
    }
    func commit(ticket: String, text: String) async -> Bool {
        // The real IME applies this same policy before consuming the context-bound ticket.
        guard VoiceInsertionPolicy.allowsAutomaticInsertion(text: text, applicationID: "com.mitchellh.ghostty") else {
            return false
        }
        committed.append(text)
        return true
    }
    func cancel(ticket: String) {}
}

@Test @MainActor func nativeTerminalDeliveryDoesNotFallBackToCopyOrCommitTwice() async {
    let bridge = NativeDeliveryFixture()
    let delivery = VoiceDelivery(bridge: bridge, currentPID: { 42 }, snapshot: {
        .init(blocked: false, target: nil)
    })
    #expect(await delivery.prepare())
    let text = VoiceInsertionPolicy.singleLineText("请检查这个问题。\n不要自动发送。")
    let accepted = await withCheckedContinuation { continuation in
        delivery.finish(text, allowed: true) { continuation.resume(returning: $0) }
    }
    #expect(accepted)
    #expect(delivery.failureReason == nil)
    #expect(bridge.committed == ["请检查这个问题。 不要自动发送。"])
    let duplicate = await withCheckedContinuation { continuation in
        delivery.finish(text, allowed: true) { continuation.resume(returning: $0) }
    }
    #expect(!duplicate)
    #expect(bridge.committed.count == 1)
}

@Test @MainActor func changedTargetStillDoesNotReceiveTerminalText() async {
    let bridge = NativeDeliveryFixture()
    let delivery = VoiceDelivery(bridge: bridge, currentPID: { 42 }, snapshot: {
        .init(blocked: false, target: nil)
    })
    #expect(await delivery.prepare())
    let accepted = await withCheckedContinuation { continuation in
        delivery.finish("不应该写入", allowed: false) { continuation.resume(returning: $0) }
    }
    #expect(!accepted)
    #expect(bridge.committed.isEmpty)
    #expect(delivery.failureReason == "输入目标已变化，未自动填入")
}
