import Foundation
import Testing
@testable import RoTypeApp

@MainActor
struct VoiceActivationTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "RoType.voice-activation-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func preparesOnlyWhenLuokeIsSelected() {
        withDefaults { defaults in
            var selected = false
            var preparations = 0
            let activation = VoiceActivation(defaults: defaults, isSelected: { selected })
            #expect(!activation.isObserving)
            activation.start { preparations += 1 }
            #expect(activation.isObserving)
            #expect(activation.requested)
            #expect(preparations == 0)
            selected = true
            activation.refresh()
            #expect(preparations == 1)
            selected = false
            activation.refresh()
            #expect(preparations == 1)
            activation.stop()
        }
    }

    @Test func explicitOffSurvivesRestartAndSourceChanges() {
        withDefaults { defaults in
            let first = VoiceActivation(defaults: defaults, isSelected: { true })
            first.setRequested(false)
            let restored = VoiceActivation(defaults: defaults, isSelected: { true })
            var preparations = 0
            restored.start { preparations += 1 }
            restored.refresh()
            #expect(!restored.requested)
            #expect(preparations == 0)
            restored.stop()
        }
    }

    @Test func shutdownDoesNotOverwriteUserIntent() {
        withDefaults { defaults in
            let activation = VoiceActivation(defaults: defaults, isSelected: { true })
            activation.setRequested(true)
            activation.start {}
            activation.stop()
            #expect(!activation.isObserving)
            #expect(VoiceActivation(defaults: defaults).requested)
        }
    }

    @Test func legacyRuntimeFailureIsNotAnExplicitOffPreference() {
        withDefaults { defaults in
            defaults.set(false, forKey: "voice.enabled")
            #expect(VoiceActivation(defaults: defaults).requested)
            defaults.set(false, forKey: VoiceActivation.preferenceKey)
            #expect(!VoiceActivation(defaults: defaults).requested)
        }
    }
}
