import Foundation

let mode = CommandLine.arguments.dropFirst().first ?? "translation"
let expected = CommandLine.arguments.dropFirst(2).first ?? "accepted"
let serviceName = CommandLine.arguments.dropFirst(3).first ?? ""
let prefix = "im.roarkai.inputmethod.Luoke.translation.test."
guard serviceName.hasPrefix(prefix), UUID(uuidString: String(serviceName.dropFirst(prefix.count))) != nil else {
    fputs("An isolated test service name is required.\n", stderr)
    exit(EXIT_FAILURE)
}
let connection = NSXPCConnection(machServiceName: serviceName)
connection.remoteObjectInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
connection.resume()

let completed = DispatchSemaphore(value: 0)
let lock = NSLock()
var outcome = "timeout"
func finish(_ value: String) {
    lock.lock()
    defer { lock.unlock() }
    guard outcome == "timeout" else { return }
    outcome = value
    completed.signal()
}

let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
    finish("connection-rejected")
} as! RoTypeTranslationXPCProtocol

func translationReply(_ generation: Int64, _ direction: String?, _ source: String?, _ text: String?, _ error: Error?) {
    guard let error = error as NSError?, error.domain == ROTYPE_TRANSLATION_SERVICE_NAME else {
        finish("unexpected-response")
        return
    }
    switch error.code {
    case 1: finish("accepted") // authenticated caller reached request validation
    case 5: finish("operation-rejected")
    case 6: finish("version-rejected")
    default: finish("unexpected-error")
    }
}

switch mode {
case "candidate", "candidate-version":
    proxy.translateCandidate(sessionID: UUID().uuidString, generation: 1,
        request: ["version": mode == "candidate-version" ? "99" : "2",
                  "rawInput": "cafe", "sourceText": "café", "scope": "whole",
                  "identity": "0:4:0", "direction": "zh-en"], withReply: translationReply)
case "verification":
    proxy.controllerInputGeneration { _, error in
        finish(error == nil ? "accepted" : "operation-rejected")
    }
default:
    proxy.translate(
        sessionID: UUID().uuidString,
        generation: 1,
        rawInput: "",
        sourceText: "",
        withReply: translationReply
    )
}

_ = completed.wait(timeout: .now() + 5)
lock.lock()
let observed = outcome
outcome = "finished"
lock.unlock()
connection.invalidate()
if observed != expected {
    fputs("Expected \(expected), got \(observed)\n", stderr)
    exit(EXIT_FAILURE)
}
print("XPC \(mode) client \(observed)")
