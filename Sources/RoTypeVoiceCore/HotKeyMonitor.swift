import ApplicationServices
import Foundation

public enum HotKeyMonitorError: LocalizedError {
    case inputMonitoringPermissionMissing
    case eventTapCreationFailed

    public var errorDescription: String? {
        switch self {
        case .inputMonitoringPermissionMissing:
            "需要在系统设置 → 隐私与安全性 → 输入监控中允许 RoType Voice，然后重新启动。"
        case .eventTapCreationFailed:
            "macOS 无法创建右 Option 监听器，请重新启动 RoType Voice。"
        }
    }
}

@MainActor
public final class HotKeyMonitor {
    public var onPressed: (@MainActor () -> Void)?
    public var onReleased: (@MainActor () -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    public init() {}

    public func start() throws {
        guard eventTap == nil else { return }
        guard requestInputMonitoringIfNeeded() else {
            throw HotKeyMonitorError.inputMonitoringPermissionMissing
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard type == .flagsChanged, let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                guard keyCode == 61 else { return Unmanaged.passUnretained(event) }

                let pressed = event.flags.contains(.maskAlternate)
                Task { @MainActor in monitor.update(pressed: pressed) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            throw HotKeyMonitorError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    public func requestInputMonitoringIfNeeded() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return CGRequestListenEventAccess()
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        isPressed = false
    }

    private func update(pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        if pressed {
            onPressed?()
        } else {
            onReleased?()
        }
    }

}
