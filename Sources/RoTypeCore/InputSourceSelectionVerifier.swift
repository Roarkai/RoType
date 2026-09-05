public enum InputSourceSelectionVerifier {
    public static func isVerified(
        targetIdentifier: String,
        currentIdentifier: String?,
        controllerHandledInput: Bool
    ) -> Bool {
        currentIdentifier == targetIdentifier && controllerHandledInput
    }

    public static func hasFreshControllerInput(baseline: Int64, current: Int64) -> Bool {
        current > baseline
    }
}
