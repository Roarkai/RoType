import Foundation

public enum VoiceInsertionPolicy {
    /// Dictation is a single paragraph: paragraph separators become spaces, never Return events.
    /// Other controls (Tab, Escape, etc.) remain rejected by the native commit gate.
    public static func singleLineText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func allowsAutomaticInsertion(text: String, applicationID: String?) -> Bool {
        guard let applicationID, !applicationID.isEmpty, !text.isEmpty,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              text.rangeOfCharacter(from: .newlines) == nil else { return false }
        // Terminals accept native IMK text too. Safety comes from the validated target,
        // one-use ticket and control-free text, not a blanket application blacklist.
        return true
    }
}
