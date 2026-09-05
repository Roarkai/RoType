import AppKit
import Security

private func isTrustedRoTypeProcess(_ application: NSRunningApplication, identifier: String) -> Bool {
    var code: SecCode?
    let attributes = [kSecGuestAttributePid: NSNumber(value: application.processIdentifier)] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
          let code else { return false }
    var requirement: SecRequirement?
    let text = "anchor apple generic and certificate leaf[subject.OU] = \"DF7J2VBQD8\" and identifier \"\(identifier)\""
    guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
          let requirement else { return false }
    return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
}

if CommandLine.arguments.contains("--quit") {
    let bundleID = Bundle.main.bundleIdentifier ?? "im.roarkai.inputmethod.Luoke.helper"
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let executableURL = Bundle.main.executableURL?.resolvingSymlinksInPath().standardizedFileURL
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter {
            $0.processIdentifier != currentPID
                && $0.executableURL?.resolvingSymlinksInPath().standardizedFileURL == executableURL
                && isTrustedRoTypeProcess($0, identifier: bundleID)
        }
    applications.forEach { $0.terminate() }
    let deadline = Date().addingTimeInterval(2)
    while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    applications.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    exit(EXIT_SUCCESS)
}

// Read-only, per-user installer query. Never activates an existing instance,
// creates a window, downloads a pack, or treats historical setup as live proof.
if CommandLine.arguments.contains("--setup-state") {
    let settings = RoTypeSettings()
    if settings.onboardingCompleted {
        print("complete")
    } else if settings.setupDeferred {
        print("deferred")
    } else {
        print(settings.keyboardVerified ? "resume" : "new")
    }
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
