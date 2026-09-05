import Foundation
import RoTypeCore
import Testing
@testable import RoTypeTranslationService

@MainActor
private final class FakeTranslator: DynamicTextTranslating {
    func translate(_ text: String, direction: DynamicTranslationDirection) async throws -> String {
        if text == "slow" {
            try await Task.sleep(for: .seconds(1))
        }
        return "translated:\(text)"
    }
}

private struct Reply: Sendable {
    let generation: Int64
    let translatedText: String?
    let errorCode: Int?
}

@Test @MainActor
func coordinatorRejectsOutOfOrderGenerationWithoutCancellingLatest() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let connectionID = UUID()
    let sessionID = UUID().uuidString
    let replies = AsyncStream<Reply> { continuation in
        let reply: @Sendable (Int64, String?, String?, String?, NSError?) -> Void = {
            generation, _, _, translatedText, error in
            continuation.yield(.init(
                generation: generation,
                translatedText: translatedText,
                errorCode: error?.code
            ))
        }
        coordinator.translate(
            connectionID: connectionID,
            sessionID: sessionID,
            generation: 2,
            rawInput: "hello",
            sourceText: "hello",
            withReply: reply
        )
        coordinator.translate(
            connectionID: connectionID,
            sessionID: sessionID,
            generation: 1,
            rawInput: "old",
            sourceText: "old",
            withReply: reply
        )
    }

    var received: [Reply] = []
    for await reply in replies {
        received.append(reply)
        if received.count == 2 { break }
    }

    #expect(received.contains { $0.generation == 1 && $0.errorCode == 2 })
    #expect(received.contains { $0.generation == 2 && $0.translatedText == "translated:hello" })
}

@Test @MainActor
func coordinatorCancellationRepliesAndReleasesTask() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let connectionID = UUID()
    let sessionID = UUID().uuidString
    let reply = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: connectionID,
            sessionID: sessionID,
            generation: 1,
            rawInput: "slow",
            sourceText: "slow"
        ) { generation, _, _, _, error in
            continuation.resume(returning: Reply(
                generation: generation,
                translatedText: nil,
                errorCode: error?.code
            ))
        }
        coordinator.cancel(connectionID: connectionID, sessionID: sessionID, throughGeneration: 1)
    }
    #expect(reply.generation == 1)
    #expect(reply.errorCode == 4)
}

@Test @MainActor
func selectedChineseCandidateIsNotOverriddenByEnglishLookingPinyin() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let response = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: UUID(),
            sessionID: UUID().uuidString,
            generation: 1,
            rawInput: "can",
            sourceText: "餐"
        ) { _, direction, source, text, error in
            continuation.resume(returning: (direction, source, text, error?.code))
        }
    }
    #expect(response.0 == "zh-en")
    #expect(response.1 == "餐")
    #expect(response.2 == "translated:餐")
    #expect(response.3 == nil)
}

@Test(arguments: ["hello", "café", "cafe\u{301}", "don’t"]) @MainActor
func selectedEnglishCompletionIsTranslatedInsteadOfItsInputCode(_ selected: String) async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let response = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: UUID(),
            sessionID: UUID().uuidString,
            generation: 1,
            rawInput: "hel",
            sourceText: selected
        ) { _, direction, source, text, error in
            continuation.resume(returning: (direction, source, text, error?.code))
        }
    }
    #expect(response.0 == "en-zh")
    #expect(response.1 == selected)
    #expect(response.2 == "translated:\(selected)")
    #expect(response.3 == nil)
}

@Test(arguments: [("café", "en-zh"), ("OpenAI你好", "zh-en"), ("𠀀", "zh-en")]) @MainActor
func versionedCandidateRequestUsesExplicitSource(_ selected: String, _ requestedDirection: String) async {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(backend: FakeTranslator()), role: .inputMethod)
    let response = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: UUID().uuidString, generation: 1,
            request: ["version": "2", "rawInput": "cafe", "sourceText": selected,
                      "identity": "0:4:0", "scope": "whole", "direction": requestedDirection]) { _, direction, source, text, error in
            continuation.resume(returning: (direction, source, text, (error as NSError?)?.code))
        }
    }
    #expect(response.0 == requestedDirection)
    #expect(response.1 == selected)
    #expect(response.2 == "translated:\(selected)")
    #expect(response.3 == nil)
}

@Test(arguments: [("version", "99", 6), ("direction", "zh-en", 1), ("scope", "unknown", 1),
                  ("identity", "0:99:0", 1), ("rawInput", "", 1), ("extra", "ignored?", 1),
                  ("sourceText", "привет", 1)]) @MainActor
func invalidCandidateRequestDoesNotConsumeGeneration(_ key: String, _ value: String, _ expectedCode: Int) async {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(backend: FakeTranslator()), role: .inputMethod)
    let sessionID = UUID().uuidString
    let valid = ["version": "2", "rawInput": "cafe", "sourceText": "café",
                 "identity": "0:4:0", "scope": "segment", "direction": "en-zh"]
    var invalid = valid
    invalid[key] = value
    let rejected = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: sessionID, generation: 1, request: invalid) { _, _, _, text, error in
            continuation.resume(returning: (text, (error as NSError?)?.code))
        }
    }
    #expect(rejected.0 == nil)
    #expect(rejected.1 == expectedCode)
    let accepted = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: sessionID, generation: 1, request: valid) { _, _, _, text, error in
            continuation.resume(returning: (text, (error as NSError?)?.code))
        }
    }
    #expect(accepted.0 == "translated:café")
    #expect(accepted.1 == nil)
}

@Test @MainActor
func settingsRoleCannotSubmitVersionedTranslation() async {
    let service = TranslationXPCService(coordinator: TranslationCoordinator(backend: FakeTranslator()), role: .settingsHelper)
    let code = await withCheckedContinuation { continuation in
        service.translateCandidate(sessionID: UUID().uuidString, generation: 1, request: [:]) { _, _, _, _, error in
            continuation.resume(returning: (error as NSError?)?.code)
        }
    }
    #expect(code == 5)
}

@Test @MainActor
func coordinatorTracksFreshControllerInput() {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    #expect(coordinator.currentControllerInputGeneration() == 0)
    coordinator.recordControllerInput()
    #expect(coordinator.currentControllerInputGeneration() == 1)
}

@Test @MainActor
func settingsRoleCannotSubmitTranslation() async {
    let service = TranslationXPCService(
        coordinator: TranslationCoordinator(backend: FakeTranslator()),
        role: .settingsHelper
    )
    let errorCode = await withCheckedContinuation { continuation in
        service.translate(
            sessionID: UUID().uuidString,
            generation: 1,
            rawInput: "hello",
            sourceText: "hello"
        ) { _, _, _, _, error in
            continuation.resume(returning: (error as NSError?)?.code)
        }
    }
    #expect(errorCode == 5)
}

@Test @MainActor
func coordinatorRejectsNonUUIDSession() async {
    let coordinator = TranslationCoordinator(backend: FakeTranslator())
    let reply = await withCheckedContinuation { continuation in
        coordinator.translate(
            connectionID: UUID(),
            sessionID: "1",
            generation: 1,
            rawInput: "hello",
            sourceText: "hello"
        ) { generation, _, _, _, error in
            continuation.resume(returning: Reply(
                generation: generation,
                translatedText: nil,
                errorCode: error?.code
            ))
        }
    }
    #expect(reply.generation == 1)
    #expect(reply.errorCode == 1)
}
