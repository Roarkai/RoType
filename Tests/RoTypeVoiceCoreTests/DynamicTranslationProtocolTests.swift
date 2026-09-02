import Foundation
import Testing
@testable import RoTypeVoiceCore

@Test func dynamicTranslationRequestRoundTripsUnicodeAndNewlines() throws {
    let request = DynamicTranslationRequest(rawInput: "ni'zai'gan'ma", topCandidate: "你在干嘛\n吗？")
    #expect(DynamicTranslationRequest(data: request.encoded()) == request)
}

@Test func dynamicTranslationResponseRoundTrips() throws {
    let request = DynamicTranslationRequest(rawInput: "hello", topCandidate: "hello")
    let response = DynamicTranslationResponse(
        request: request,
        direction: .englishToChinese,
        sourceText: "hello",
        translatedText: "你好"
    )
    #expect(DynamicTranslationResponse(data: response.encoded()) == response)
}

@Test func malformedBridgePayloadIsRejected() {
    #expect(DynamicTranslationRequest(data: Data("v2\n%61\n%62\n".utf8)) == nil)
    #expect(DynamicTranslationResponse(data: Data("v1\n%61\n".utf8)) == nil)
}

@Test func bridgeProcessesOnlyFreshRequests() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(DynamicTranslationBridgePolicy.shouldProcessRequest(
        modifiedAt: now.addingTimeInterval(-2),
        now: now
    ))
    #expect(!DynamicTranslationBridgePolicy.shouldProcessRequest(
        modifiedAt: now.addingTimeInterval(-11),
        now: now
    ))
    #expect(!DynamicTranslationBridgePolicy.shouldProcessRequest(
        modifiedAt: now.addingTimeInterval(1),
        now: now
    ))
}
