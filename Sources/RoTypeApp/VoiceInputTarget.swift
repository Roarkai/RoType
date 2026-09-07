import ApplicationServices

/// Read-only focus observation. Native IMK owns insertion, so an app need not
/// expose AXSelectedText as writable (many chat applications do not).
struct VoiceInputTarget: @unchecked Sendable {
    struct Snapshot: Sendable {
        let blocked: Bool
        let target: VoiceInputTarget?
    }
    let element: AXUIElement
    let pid: pid_t
    let selection: CFRange?

    static func snapshot() -> Snapshot {
        guard let element = focusedElement() else { return Snapshot(blocked: false, target: nil) }
        guard !isSecure(element) else { return Snapshot(blocked: true, target: nil) }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return Snapshot(blocked: false, target: nil) }
        return Snapshot(blocked: false,
                        target: VoiceInputTarget(element: element, pid: pid, selection: selectedRange(element)))
    }

    var isCurrent: Bool {
        guard let focused = Self.focusedElement(), CFEqual(focused, element),
              !Self.isSecure(element) else { return false }
        guard let selection else { return true }
        guard let range = Self.selectedRange(element) else { return false }
        return range.location == selection.location && range.length == selection.length
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
            || (attribute(element, "AXProtectedContent") as? Bool) == true
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.03)
        guard let value = attribute(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.03)
        return element
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let typed = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(typed) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(typed, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }
}
