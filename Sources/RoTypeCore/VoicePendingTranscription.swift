import Foundation

/// A completed recording waits for model readiness, without requiring another Fn press.
public struct VoicePendingTranscription: Sendable {
    public struct Request: Sendable {
        public let id: UUID
        public let audio: URL
    }
    private var pending: Request?
    public init() {}
    public mutating func enqueue(id: UUID, audio: URL) { pending = Request(id: id, audio: audio) }
    public mutating func cancel() { pending = nil }
    public mutating func take(ready: Bool) -> Request? {
        guard ready else { return nil }
        defer { pending = nil }
        return pending
    }
}
