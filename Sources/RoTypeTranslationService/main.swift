import Foundation
import RoTypeXPCProtocol

#if ROTYPE_XPC_TEST
// Only the separately compiled integration fixture can choose a service name.
// The shipped executable has neither an argument nor an environment override.
let serviceName = CommandLine.arguments.dropFirst().first ?? ""
let testPrefix = "im.roarkai.inputmethod.Luoke.translation.test."
guard serviceName.hasPrefix(testPrefix),
      UUID(uuidString: String(serviceName.dropFirst(testPrefix.count))) != nil else {
    fatalError("An isolated XPC fixture service name is required.")
}
#else
let serviceName = ROTYPE_TRANSLATION_SERVICE_NAME
#endif

let delegate = TranslationXPCListenerDelegate()
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
