import Foundation
import Testing
@testable import RoTypeApp

@MainActor
private func withSettings(_ body: (UserDefaults) async -> Void) async {
    let name = "RoType.SetupTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    await body(defaults)
}

@Test @MainActor func setupResumesWithoutRepeatingKeyboardVerification() async {
    await withSettings { defaults in
        let first = RoTypeSettings(defaults: defaults)
        first.recordKeyboardVerification()
        let reopened = RoTypeSettings(defaults: defaults)
        #expect(reopened.keyboardVerified)
        #expect(reopened.initialOnboardingStep == 1)
        #expect(reopened.keyboardStepComplete(isReady: true, currentVerification: false))
        #expect(!reopened.keyboardStepComplete(isReady: false, currentVerification: false))
    }
}

@Test @MainActor func legacyCompletedSetupIsNotResetByAnUpgrade() async {
    await withSettings { defaults in
        defaults.set(true, forKey: "onboarding.completed.keyboard-and-translation")
        let upgraded = RoTypeSettings(defaults: defaults)
        #expect(upgraded.onboardingCompleted)
        #expect(upgraded.keyboardVerified)
    }
}

@Test @MainActor func translationPreparationCanBeExplicitlyDeferred() async {
    await withSettings { defaults in
        let settings = RoTypeSettings(defaults: defaults)
        settings.recordKeyboardVerification()
        settings.setTranslationReady(false)
        #expect(!settings.canFinishSetup(isReady: true, currentVerification: false))
        settings.translationDeferred = true
        #expect(settings.canFinishSetup(isReady: true, currentVerification: false))
        #expect(!settings.canFinishSetup(isReady: false, currentVerification: false))
        settings.onboardingCompleted = true
        let reopened = RoTypeSettings(defaults: defaults)
        #expect(reopened.onboardingCompleted && reopened.translationDeferred)
        #expect(!reopened.translationReady) // historical progress is not current capability evidence
    }
}

@Test @MainActor func closingSetupRemembersDeferralWithoutClaimingCompletion() async {
    await withSettings { defaults in
        let settings = RoTypeSettings(defaults: defaults)
        settings.recordKeyboardVerification()
        settings.setupDeferred = true
        let reopened = RoTypeSettings(defaults: defaults)
        #expect(reopened.setupDeferred && reopened.keyboardVerified)
        #expect(!reopened.onboardingCompleted)
        reopened.restartOnboarding()
        let restarted = RoTypeSettings(defaults: defaults)
        #expect(!restarted.keyboardVerified && !restarted.setupDeferred)
    }
}

@Test @MainActor func olderSystemsCanFinishWithStaticTranslation() async {
    await withSettings { defaults in
        let settings = RoTypeSettings(defaults: defaults, probe: { .staticOnly })
        await settings.refreshTranslationAvailability()
        #expect(settings.canFinishSetup(isReady: true, currentVerification: true))
        #expect(!settings.canFinishSetup(isReady: true, currentVerification: false))
    }
}

@Test @MainActor func installedLanguagePacksAreDetectedWithoutPreparingAgain() async {
    await withSettings { defaults in
        let settings = RoTypeSettings(defaults: defaults, probe: { .ready })
        #expect(settings.translationStatus == .checking)
        await settings.refreshTranslationAvailability()
        #expect(settings.translationReady)
    }
}

@Test @MainActor func lateAvailabilityProbeCannotOverwriteSuccessfulPreparation() async {
    await withSettings { defaults in
        var reply: CheckedContinuation<RoTypeSettings.TranslationStatus, Never>?
        let settings = RoTypeSettings(defaults: defaults, probe: {
            await withCheckedContinuation { reply = $0 }
        })
        let pending = Task { await settings.refreshTranslationAvailability() }
        while reply == nil { await Task.yield() }
        settings.setTranslationReady(true)
        reply?.resume(returning: .needsPreparation)
        await pending.value
        #expect(settings.translationReady)
    }
}
