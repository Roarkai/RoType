import Testing
@testable import RoTypeApp

@MainActor
private final class MissingNativeTarget: VoiceCommitTransport {
    var commits = 0
    var onCapture: () -> Void = {}
    func capture(applicationPID: Int32) async -> VoiceCommitBridge.Capture? { onCapture(); return nil }
    func commit(ticket: String, text: String) async -> Bool { commits += 1; return true }
    func cancel(ticket: String) {}
}

@Test @MainActor func missingNativeInputContextMustNotPreventRecording() async {
    let bridge = MissingNativeTarget()
    let delivery = VoiceDelivery(bridge: bridge, currentPID: { 42 }, snapshot: {
        VoiceInputTarget.Snapshot(blocked: false, target: nil)
    })
    let canRecord = await delivery.prepare()
    #expect(canRecord, "An unavailable IMK context must fall back to a retained transcript, not block the microphone")
    let inserted = await withCheckedContinuation { continuation in
        delivery.finish("只填入，不发送。", allowed: true) { continuation.resume(returning: $0) }
    }
    #expect(!inserted)
    #expect(bridge.commits == 0)
    #expect(delivery.failureReason == "当前输入框未建立输入连接，文字已保留")
}

@Test @MainActor func cancellationDuringNativeCaptureCannotStartRecording() async {
    let bridge = MissingNativeTarget()
    let delivery = VoiceDelivery(bridge: bridge, currentPID: { 42 }, snapshot: {
        VoiceInputTarget.Snapshot(blocked: false, target: nil)
    })
    bridge.onCapture = { [weak delivery] in delivery?.cancel() }
    let canRecord = await delivery.prepare()
    #expect(!canRecord)
}

@Test @MainActor func secureFocusAppearingDuringCaptureStillBlocksRecording() async {
    var snapshots = 0
    let delivery = VoiceDelivery(bridge: MissingNativeTarget(), currentPID: { 42 }, snapshot: {
        snapshots += 1
        return VoiceInputTarget.Snapshot(blocked: snapshots > 1, target: nil)
    })
    let canRecord = await delivery.prepare()
    #expect(!canRecord)
}

@Test @MainActor func secureInputStillPreventsRecording() async {
    let delivery = VoiceDelivery(bridge: MissingNativeTarget(), currentPID: { 42 }, snapshot: {
        VoiceInputTarget.Snapshot(blocked: true, target: nil)
    })
    let canRecord = await delivery.prepare()
    #expect(!canRecord)
}
