import Foundation

public enum TextChunker {
    /// Core Graphics text events are more reliable when long strings are posted
    /// in small UTF-16 chunks. Never split a composed character sequence.
    public static func chunks(_ text: String, maximumUTF16Length: Int = 20) -> [String] {
        precondition(maximumUTF16Length > 0)

        var result: [String] = []
        var current = ""
        var currentLength = 0

        for character in text {
            let part = String(character)
            let partLength = part.utf16.count

            if !current.isEmpty && currentLength + partLength > maximumUTF16Length {
                result.append(current)
                current = ""
                currentLength = 0
            }

            current.append(character)
            currentLength += partLength
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
