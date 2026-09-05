import Foundation

// Read-only observer of the installed service. Keep one authenticated connection
// open so natural idle exit cannot be mistaken for interference from the test.
let readyPath = CommandLine.arguments[1]
let connection = NSXPCConnection(machServiceName: ROTYPE_TRANSLATION_SERVICE_NAME)
connection.remoteObjectInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
connection.interruptionHandler = { exit(2) }
connection.invalidationHandler = { exit(3) }
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { _ in exit(4) } as! RoTypeTranslationXPCProtocol
proxy.controllerInputGeneration { _, error in
    guard error == nil else { exit(5) }
    do {
        try Data("ready".utf8).write(to: URL(fileURLWithPath: readyPath), options: .atomic)
    } catch { exit(6) }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    if !FileManager.default.fileExists(atPath: readyPath) { exit(7) }
}
dispatchMain()
