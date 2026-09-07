import Foundation

/// One recording owns one result. Cancellation is final, even if the worker replies late.
public struct VoiceSession: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case recording(UUID)
        case recognizing(UUID)
    }

    public private(set) var state: State = .idle
    private var targetValid = false

    public init() {}

    public mutating func begin() -> UUID? {
        guard state == .idle else { return nil }
        let id = UUID()
        state = .recording(id)
        targetValid = true
        return id
    }

    public mutating func stop() -> UUID? {
        guard case .recording(let id) = state else { return nil }
        state = .recognizing(id)
        return id
    }

    public mutating func invalidateTarget() { targetValid = false }

    public mutating func cancel() {
        state = .idle
        targetValid = false
    }

    /// nil = stale result; false = keep for manual copying; true = revalidate target before insertion.
    public mutating func takeResult(id: UUID) -> Bool? {
        guard state == .recognizing(id) else { return nil }
        let deliver = targetValid
        cancel()
        return deliver
    }
}
