import Combine
import Foundation
@preconcurrency import Translation

@MainActor
final class RoTypeSettings: ObservableObject {
    enum TranslationStatus: Equatable {
        case checking, ready, needsPreparation, staticOnly
    }

    private enum Key {
        static let onboardingCompleted = "onboarding.completed.keyboard-and-translation"
        static let keyboardVerified = "onboarding.keyboard-verified"
        static let translationDeferred = "onboarding.translation-deferred"
        static let setupDeferred = "onboarding.setup-deferred"
    }

    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }
    @Published private(set) var keyboardVerified: Bool
    @Published var setupDeferred: Bool {
        didSet { defaults.set(setupDeferred, forKey: Key.setupDeferred) }
    }
    @Published var translationDeferred: Bool {
        didSet { defaults.set(translationDeferred, forKey: Key.translationDeferred) }
    }
    @Published private(set) var translationStatus = TranslationStatus.checking

    var translationReady: Bool { translationStatus == .ready }
    var initialOnboardingStep: Int { keyboardVerified ? 1 : 0 }

    private let defaults: UserDefaults
    private let probe: @MainActor () async -> TranslationStatus
    private var probeGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        probe: @escaping @MainActor () async -> TranslationStatus = {
            await RoTypeSettings.systemTranslationAvailability()
        }
    ) {
        self.defaults = defaults
        self.probe = probe
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        keyboardVerified = defaults.bool(forKey: Key.keyboardVerified)
            || defaults.bool(forKey: Key.onboardingCompleted)
        translationDeferred = defaults.bool(forKey: Key.translationDeferred)
        setupDeferred = defaults.bool(forKey: Key.setupDeferred)
    }

    func recordKeyboardVerification() {
        keyboardVerified = true
        defaults.set(true, forKey: Key.keyboardVerified)
    }

    func keyboardStepComplete(isReady: Bool, currentVerification: Bool) -> Bool {
        isReady && (keyboardVerified || currentVerification)
    }

    func canFinishSetup(isReady: Bool, currentVerification: Bool) -> Bool {
        keyboardStepComplete(isReady: isReady, currentVerification: currentVerification)
            && (translationReady || translationDeferred || translationStatus == .staticOnly)
    }

    func restartOnboarding() {
        keyboardVerified = false
        defaults.set(false, forKey: Key.keyboardVerified)
        onboardingCompleted = false
        setupDeferred = false
    }

    func setTranslationReady(_ ready: Bool) {
        probeGeneration += 1
        translationStatus = ready ? .ready : .needsPreparation
    }

    func refreshTranslationAvailability() async {
        probeGeneration += 1
        let generation = probeGeneration
        translationStatus = .checking
        let result = await probe()
        guard !Task.isCancelled, generation == probeGeneration else { return }
        translationStatus = result
    }

    private static func systemTranslationAvailability() async -> TranslationStatus {
        guard #available(macOS 26.0, *) else { return .staticOnly }
        let availability = LanguageAvailability()
        let chinese = Locale.Language(identifier: "zh-Hans")
        let english = Locale.Language(identifier: "en")
        let zhEN = await availability.status(from: chinese, to: english)
        let enZH = await availability.status(from: english, to: chinese)
        return zhEN == .installed && enZH == .installed ? .ready : .needsPreparation
    }
}
