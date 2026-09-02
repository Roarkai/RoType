import ApplicationServices
import Foundation

public enum TextInsertionError: LocalizedError {
    case accessibilityPermissionMissing
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "需要在系统设置 → 隐私与安全性 → 辅助功能中允许 RoType Voice。"
        case .eventCreationFailed:
            "macOS 无法创建文字输入事件。"
        }
    }
}

public struct TextInserter: Sendable {
    public init() {}

    @MainActor
    public func requestAccessibilityIfNeeded() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func insert(_ text: String) throws {
        guard AXIsProcessTrusted() else {
            throw TextInsertionError.accessibilityPermissionMissing
        }

        for chunk in TextChunker.chunks(text) {
            guard
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                throw TextInsertionError.eventCreationFailed
            }

            let units = Array(chunk.utf16)
            units.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
