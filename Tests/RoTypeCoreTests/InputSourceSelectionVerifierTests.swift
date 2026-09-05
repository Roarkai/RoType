import Testing
@testable import RoTypeCore

@Test func rejectsStaleSelectedFlagWhenAnotherInputSourceIsCurrent() {
    #expect(!InputSourceSelectionVerifier.isVerified(
        targetIdentifier: "im.roarkai.inputmethod.Luoke.Hans",
        currentIdentifier: "com.bytedance.inputmethod.doubaoime.pinyin",
        controllerHandledInput: true
    ))
}

@Test func rejectsMatchingTISStateWithoutControllerInputEvidence() {
    #expect(!InputSourceSelectionVerifier.isVerified(
        targetIdentifier: "im.roarkai.inputmethod.Luoke.Hans",
        currentIdentifier: "im.roarkai.inputmethod.Luoke.Hans",
        controllerHandledInput: false
    ))
}

@Test func acceptsOnlyNewControllerInputGeneration() {
    #expect(InputSourceSelectionVerifier.hasFreshControllerInput(baseline: 4, current: 5))
    #expect(!InputSourceSelectionVerifier.hasFreshControllerInput(baseline: 4, current: 4))
    #expect(!InputSourceSelectionVerifier.hasFreshControllerInput(baseline: 4, current: 3))
}

@Test func verifiesExactCurrentInputSourceWithControllerInputEvidence() {
    #expect(InputSourceSelectionVerifier.isVerified(
        targetIdentifier: "im.roarkai.inputmethod.Luoke.Hans",
        currentIdentifier: "im.roarkai.inputmethod.Luoke.Hans",
        controllerHandledInput: true
    ))
    #expect(!InputSourceSelectionVerifier.isVerified(
        targetIdentifier: "im.roarkai.inputmethod.Luoke.Hans",
        currentIdentifier: "im.roarkai.inputmethod.Luoke",
        controllerHandledInput: true
    ))
    #expect(!InputSourceSelectionVerifier.isVerified(
        targetIdentifier: "im.roarkai.inputmethod.Luoke.Hans",
        currentIdentifier: nil,
        controllerHandledInput: true
    ))
}
