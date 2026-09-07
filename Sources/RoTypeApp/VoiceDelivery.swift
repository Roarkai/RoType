import AppKit

/// Owns capture, cancellation and one native insertion. AX is observation-only.
@MainActor
final class VoiceDelivery {
    private let bridge: any VoiceCommitTransport
    private let currentPID: () -> pid_t?
    private let snapshot: () async -> VoiceInputTarget.Snapshot

    init(bridge: any VoiceCommitTransport = VoiceCommitBridge(),
         currentPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         snapshot: @escaping () async -> VoiceInputTarget.Snapshot = {
             await Task.detached { VoiceInputTarget.snapshot() }.value
         }) {
        self.bridge = bridge
        self.currentPID = currentPID
        self.snapshot = snapshot
    }
    private var generation = UUID()
    private var capture: VoiceCommitBridge.Capture?
    private var focus: VoiceInputTarget?
    private var applicationPID: pid_t?
    private(set) var isPending = false
    private(set) var failureReason: String?

    func prepare() async -> Bool {
        cancel()
        let id = generation
        guard let pid = currentPID() else { return false }
        let snapshot = await snapshot()
        guard generation == id, !snapshot.blocked else { return false }
        let captured = await bridge.capture(applicationPID: pid)
        let finalSnapshot = await self.snapshot()
        guard generation == id, !finalSnapshot.blocked else {
            if let captured { bridge.cancel(ticket: captured.ticket) }
            return false
        }
        // Native availability controls automatic insertion, not microphone access.
        capture = captured
        applicationPID = pid
        focus = snapshot.target
        return true
    }

    func targetIsCurrent() async -> Bool {
        guard let focus else { return true }
        return await Task.detached { focus.isCurrent }.value
    }

    func cancel() {
        failureReason = nil
        generation = UUID()
        if let capture { bridge.cancel(ticket: capture.ticket) }
        capture = nil
        focus = nil
        applicationPID = nil
        isPending = false
    }

    func finish(_ text: String, allowed: Bool, completion: @escaping @MainActor (Bool) -> Void) {
        let id = generation
        var captured = capture
        let originalFocus = focus
        let originalPID = applicationPID
        isPending = true
        Task {
            // Recover a transient IMK activation failure only when the original
            // read-only focus snapshot still proves the same target and selection.
            if allowed, captured == nil, let originalFocus, let originalPID,
               currentPID() == originalPID,
               await Task.detached(operation: { originalFocus.isCurrent }).value {
                captured = await bridge.capture(applicationPID: originalPID)
                guard generation == id else {
                    if let captured { bridge.cancel(ticket: captured.ticket) }
                    return
                }
                let sameFocus = await targetIsCurrent()
                if currentPID() != originalPID || !sameFocus {
                    if let captured { bridge.cancel(ticket: captured.ticket) }
                    captured = nil
                }
            }
            guard generation == id else {
                if let captured { bridge.cancel(ticket: captured.ticket) }
                return
            }
            let accepted: Bool
            if allowed, let captured {
                accepted = await bridge.commit(ticket: captured.ticket, text: text)
            } else {
                if let captured { bridge.cancel(ticket: captured.ticket) }
                accepted = false
            }
            guard generation == id else { return }
            failureReason = accepted ? nil : (!allowed ? "输入目标已变化，未自动填入" :
                (captured == nil ? "当前输入框未建立输入连接，文字已保留" : "输入框未接受提交，文字已保留"))
            capture = nil
            focus = nil
            applicationPID = nil
            isPending = false
            completion(accepted)
        }
    }
}
