import AppKit
import Carbon
import Combine

/// User intent is persistent; model loading, maintenance and runtime failures are not preferences.
@MainActor
final class VoiceActivation: NSObject, ObservableObject {
    static let preferenceKey = "voice.autoEnabled"
    @Published private(set) var requested: Bool
    private let defaults: UserDefaults
    private let isSelected: () -> Bool
    private var onSelection: (() -> Void)?
    var isObserving: Bool { onSelection != nil }

    init(defaults: UserDefaults = .standard,
         isSelected: @escaping () -> Bool = { VoiceFnShortcut.isLuokeSelected() }) {
        self.defaults = defaults
        self.isSelected = isSelected
        // Old voice.enabled was also reset by maintenance and failures; do not treat it as user intent.
        requested = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
        super.init()
    }

    func setRequested(_ value: Bool) {
        requested = value
        defaults.set(value, forKey: Self.preferenceKey)
    }

    func start(onSelection: @escaping () -> Void) {
        stop()
        self.onSelection = onSelection
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil
        )
        refresh()
    }

    @objc func refresh() {
        if requested, isSelected() { onSelection?() }
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        onSelection = nil
    }
}
