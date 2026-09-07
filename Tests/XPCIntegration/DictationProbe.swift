import Foundation

// No real input client or UI events: exercise the signed rendezvous and direct wire only.
final class Destination: NSObject, NSXPCListenerDelegate, RoTypeDictationXPCProtocol {
    private var used = false
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement("im.roarkai.inputmethod.Luoke.helper"))
        connection.exportedInterface = NSXPCInterface(with: RoTypeDictationXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
    func capture(applicationPID: Int32, withReply reply: @escaping (String?, String?) -> Void) {
        reply("fixture-ticket", "dev.rotype.fixture")
    }
    func commit(ticket: String, text: String, deadline: TimeInterval, withReply reply: @escaping (Bool) -> Void) {
        let accepted = !used && ticket == "fixture-ticket" && text == "只填入，不发送。"
        used = true
        reply(accepted)
    }
    func cancel(ticket: String) {}
}

func requirement(_ identifier: String) -> String {
    "anchor apple generic and certificate leaf[subject.OU] = \"DF7J2VBQD8\" and identifier \"\(identifier)\""
}
let mode = CommandLine.arguments[1]
let serviceName = CommandLine.arguments[2]
guard serviceName.hasPrefix("im.roarkai.inputmethod.Luoke.translation.test.") else { exit(2) }
let registry = NSXPCConnection(machServiceName: serviceName)
registry.setCodeSigningRequirement(requirement("im.roarkai.inputmethod.Luoke.translation"))
registry.remoteObjectInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
registry.resume()
let proxy = registry.remoteObjectProxyWithErrorHandler { error in
    fputs("Registry failed: \(error)\n", stderr); exit(3)
} as! RoTypeTranslationXPCProtocol

if mode == "publish" {
    let destination = Destination()
    let listener = NSXPCListener.anonymous()
    listener.delegate = destination
    listener.resume()
    proxy.registerDictationEndpoint?(listener.endpoint)
    try Data("ready".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    withExtendedLifetime((listener, destination)) { RunLoop.current.run(until: Date().addingTimeInterval(40)) }
    exit(0)
}

let completed = DispatchSemaphore(value: 0)
var direct: NSXPCConnection?
if mode == "helper" {
    // A helper must not be able to poison the registered input-method endpoint.
    let decoy = NSXPCListener.anonymous()
    proxy.registerDictationEndpoint?(decoy.endpoint)
}
proxy.dictationEndpoint? { endpoint in
    if mode == "denied" {
        guard endpoint == nil else { exit(4) }
        completed.signal()
        return
    }
    guard let endpoint else { fputs("Missing dictation endpoint\n", stderr); exit(5) }
    let connection = NSXPCConnection(listenerEndpoint: endpoint)
    direct = connection
    connection.setCodeSigningRequirement(requirement("im.roarkai.inputmethod.Luoke"))
    connection.remoteObjectInterface = NSXPCInterface(with: RoTypeDictationXPCProtocol.self)
    connection.resume()
    let input = connection.remoteObjectProxyWithErrorHandler { error in
        fputs("Direct connection failed: \(error)\n", stderr); exit(6)
    } as! RoTypeDictationXPCProtocol
    input.capture(applicationPID: 42) { ticket, app in
        guard let ticket, app == "dev.rotype.fixture" else { exit(7) }
        input.commit(ticket: ticket, text: "只填入，不发送。", deadline: ProcessInfo.processInfo.systemUptime + 1) { accepted in
            guard accepted else { exit(8) }
            input.commit(ticket: ticket, text: "只填入，不发送。", deadline: ProcessInfo.processInfo.systemUptime + 1) { duplicate in
                guard !duplicate else { exit(9) }
                completed.signal()
            }
        }
    }
}
guard completed.wait(timeout: .now() + 5) == .success else { exit(10) }
direct?.invalidate()
registry.invalidate()
print("Dictation XPC \(mode) passed (no desktop text inserted).")
