public struct VoiceFnGesture: Sendable {
    public enum Action: Equatable, Sendable { case none, press, release, cancel }
    public struct Decision: Equatable, Sendable {
        public let action: Action
        public let consume: Bool
    }
    public private(set) var held = false
    private var previousFn = false

    public init() {}
    public mutating func reset() { held = false; previousFn = false }

    public func shouldFinishRecording(elapsed: Double, recorderIsRunning: Bool) -> Bool {
        !held || elapsed >= 59 || !recorderIsRunning
    }

    public mutating func flags(fn functionDown: Bool, key: Int64, otherModifiers: Bool, allowed: Bool) -> Decision {
        let changed = previousFn != functionDown
        previousFn = functionDown
        let isFnKey = key == 63 || (key == 0 && changed)
        if !functionDown, held {
            held = false
            return Decision(action: .release, consume: isFnKey && !otherModifiers)
        }
        if functionDown, changed, isFnKey, !held, !otherModifiers, allowed {
            held = true
            return Decision(action: .press, consume: true)
        }
        if held, !changed, key == 63 || key == 0, !otherModifiers {
            return Decision(action: .none, consume: true)
        }
        if held { return Decision(action: .cancel, consume: false) }
        return Decision(action: .none, consume: false)
    }
}
