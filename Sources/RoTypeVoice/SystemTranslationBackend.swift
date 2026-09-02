import Foundation
import RoTypeVoiceCore
@preconcurrency import Translation

enum DynamicTranslationBackendError: LocalizedError {
    case requiresMacOS26
    case languagePackMissing

    var errorDescription: String? {
        switch self {
        case .requiresMacOS26:
            "动态候选当前需要 macOS 26；macOS 14–15 的本地模型后端尚未安装。"
        case .languagePackMissing:
            "请先从 RoType 菜单准备中英翻译语言包。"
        }
    }
}

@MainActor
protocol DynamicTextTranslating: AnyObject {
    func translate(_ text: String, direction: DynamicTranslationResponse.Direction) async throws -> String
}

@MainActor
final class UnavailableDynamicTranslator: DynamicTextTranslating {
    func translate(_ text: String, direction: DynamicTranslationResponse.Direction) async throws -> String {
        throw DynamicTranslationBackendError.requiresMacOS26
    }
}

@available(macOS 26.0, *)
@MainActor
final class AppleDynamicTranslator: DynamicTextTranslating {
    private var chineseToEnglish: TranslationSession?
    private var englishToChinese: TranslationSession?

    func translate(_ text: String, direction: DynamicTranslationResponse.Direction) async throws -> String {
        let session = try session(for: direction)
        do {
            let response = try await session.translate(text)
            return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw DynamicTranslationBackendError.languagePackMissing
        }
    }

    private func session(for direction: DynamicTranslationResponse.Direction) throws -> TranslationSession {
        let chinese = Locale.Language(identifier: "zh-Hans")
        let english = Locale.Language(identifier: "en")

        switch direction {
        case .chineseToEnglish:
            if let chineseToEnglish { return chineseToEnglish }
            let session = TranslationSession(installedSource: chinese, target: english)
            chineseToEnglish = session
            return session
        case .englishToChinese:
            if let englishToChinese { return englishToChinese }
            let session = TranslationSession(installedSource: english, target: chinese)
            englishToChinese = session
            return session
        }
    }
}

@MainActor
enum DynamicTranslatorFactory {
    static func make() -> any DynamicTextTranslating {
        if #available(macOS 26.0, *) {
            return AppleDynamicTranslator()
        }
        return UnavailableDynamicTranslator()
    }
}
