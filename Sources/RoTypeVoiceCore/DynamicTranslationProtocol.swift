import Foundation

public enum DynamicTranslationBridgePolicy {
    public static let requestFreshnessInterval: TimeInterval = 10

    public static func shouldProcessRequest(
        modifiedAt: Date,
        now: Date = Date(),
        freshnessInterval: TimeInterval = requestFreshnessInterval
    ) -> Bool {
        let age = now.timeIntervalSince(modifiedAt)
        return age >= 0 && age <= freshnessInterval
    }
}

public struct DynamicTranslationRequest: Equatable, Sendable {
    public let rawInput: String
    public let topCandidate: String

    public init(rawInput: String, topCandidate: String) {
        self.rawInput = rawInput
        self.topCandidate = topCandidate
    }

    public init?(data: Data) {
        guard
            let payload = String(data: data, encoding: .utf8),
            let fields = PercentLineCodec.decode(payload: payload, expectedFieldCount: 2)
        else { return nil }
        self.init(rawInput: fields[0], topCandidate: fields[1])
    }

    public func encoded() -> Data {
        PercentLineCodec.encode(fields: [rawInput, topCandidate])
    }
}

public struct DynamicTranslationResponse: Equatable, Sendable {
    public enum Direction: String, Sendable {
        case chineseToEnglish = "zh-en"
        case englishToChinese = "en-zh"
    }

    public let request: DynamicTranslationRequest
    public let direction: Direction
    public let sourceText: String
    public let translatedText: String

    public init(
        request: DynamicTranslationRequest,
        direction: Direction,
        sourceText: String,
        translatedText: String
    ) {
        self.request = request
        self.direction = direction
        self.sourceText = sourceText
        self.translatedText = translatedText
    }

    public init?(data: Data) {
        guard
            let payload = String(data: data, encoding: .utf8),
            let fields = PercentLineCodec.decode(payload: payload, expectedFieldCount: 5),
            let direction = Direction(rawValue: fields[2])
        else { return nil }
        self.init(
            request: .init(rawInput: fields[0], topCandidate: fields[1]),
            direction: direction,
            sourceText: fields[3],
            translatedText: fields[4]
        )
    }

    public func encoded() -> Data {
        PercentLineCodec.encode(fields: [
            request.rawInput,
            request.topCandidate,
            direction.rawValue,
            sourceText,
            translatedText,
        ])
    }
}

private enum PercentLineCodec {
    private static let version = "v1"

    static func encode(fields: [String]) -> Data {
        let lines = [version] + fields.map(percentEncode)
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func decode(payload: String, expectedFieldCount: Int) -> [String]? {
        var lines = payload.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        guard lines.first == version, lines.count == expectedFieldCount + 1 else { return nil }
        return lines.dropFirst().map(percentDecode)
    }

    private static func percentEncode(_ value: String) -> String {
        value.utf8.map { String(format: "%%%02X", $0) }.joined()
    }

    private static func percentDecode(_ value: String) -> String {
        var bytes: [UInt8] = []
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "%" else { return "" }
            let first = value.index(after: index)
            guard first < value.endIndex else { return "" }
            let second = value.index(after: first)
            guard second < value.endIndex else { return "" }
            let end = value.index(after: second)
            guard let byte = UInt8(value[first..<end], radix: 16) else { return "" }
            bytes.append(byte)
            index = end
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
