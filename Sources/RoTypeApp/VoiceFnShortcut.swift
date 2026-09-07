import AppKit
import Carbon
import RoTypeCore

@MainActor
final class VoiceFnShortcut {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onInteraction: (() -> Void)?
    var sessionActive: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = VoiceFnGesture()

    func shouldFinishRecording(elapsed: Double, recorderIsRunning: Bool) -> Bool {
        gesture.shouldFinishRecording(elapsed: elapsed, recorderIsRunning: recorderIsRunning)
    }

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated {
                    let owner = Unmanaged<VoiceFnShortcut>.fromOpaque(context).takeUnretainedValue()
                    return owner.handle(type, event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        gesture.reset()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // No microphone, AX or process work inside the event-tap callback.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gesture.reset()
            Task { @MainActor [weak self] in self?.onCancel?() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, key == 53, gesture.held || sessionActive?() == true {
            Task { @MainActor [weak self] in self?.onCancel?() }
            return true
        }
        if type == .flagsChanged {
            let down = event.flags.contains(.maskSecondaryFn)
            let modifiers = event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
            let decision = gesture.flags(fn: down, key: key, otherModifiers: !modifiers.isEmpty,
                                         allowed: Self.isLuokeSelected() && !IsSecureEventInputEnabled())
            Task { @MainActor [weak self] in
                switch decision.action {
                case .press: self?.onPress?()
                case .release: self?.onRelease?()
                case .cancel: self?.onCancel?()
                case .none: break
                }
            }
            return decision.consume
        }
        if type == .keyDown || type == .leftMouseDown || type == .rightMouseDown {
            let cancel = gesture.held
            Task { @MainActor [weak self] in
                if cancel { self?.onCancel?() }
                self?.onInteraction?()
            }
        }
        return false
    }

    static func isLuokeSelected() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        return id == "im.roarkai.inputmethod.Luoke" || id.hasPrefix("im.roarkai.inputmethod.Luoke.")
    }
}
