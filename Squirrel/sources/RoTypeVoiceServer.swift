import AppKit
import InputMethodKit
import Security

final class RoTypeVoiceServer: NSObject, NSXPCListenerDelegate, RoTypeDictationXPCProtocol, @unchecked Sendable {
  private final class Reply<Value>: @unchecked Sendable {
    let call: (Value) -> Void
    init(_ call: @escaping (Value) -> Void) { self.call = call }
  }

  private let listener = NSXPCListener.anonymous()
  private var publisher: NSXPCConnection?
  private weak var controller: SquirrelInputController?
  private var activation = UUID()
  private var ticket = VoiceCommitTicket()
  private var ticketOwner: ObjectIdentifier?
  private var connections = Set<ObjectIdentifier>()
  private var publishAttempts = 0
  private var publication = UUID()
  private var lastHelperLaunch = Date.distantPast

  override init() {
    super.init()
    listener.delegate = self
    listener.resume()
  }

  func activate(_ controller: SquirrelInputController) {
    self.controller = controller
    activation = UUID()
    ticket.cancel()
    publishAttempts = 0
    publish()
    ensureSettingsHelper()
  }

  func deactivate(_ controller: SquirrelInputController) {
    guard self.controller === controller else { return }
    self.controller = nil
    ticket.cancel()
    activation = UUID()
  }

  func handledInput() {
    ticket.cancel()
    if publisher == nil { publishAttempts = 0 }
    publish()
  }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.setCodeSigningRequirement(Self.requirement("im.roarkai.inputmethod.Luoke.helper"))
    connection.exportedInterface = NSXPCInterface(with: RoTypeDictationXPCProtocol.self)
    connection.exportedObject = self
    let ownerID = ObjectIdentifier(connection)
    DispatchQueue.main.async { [self] in connections.insert(ownerID) }
    connection.invalidationHandler = { [weak self] in
      guard let owner = self else { return }
      DispatchQueue.main.async {
        owner.connections.remove(ownerID)
        if owner.ticketOwner == ownerID { owner.ticket.cancel() }
      }
    }
    connection.resume()
    return true
  }

  func capture(applicationPID: Int32, withReply reply: @escaping (String?, String?) -> Void) {
    let response = Reply<(String?, String?)> { reply($0.0, $0.1) }
    let ownerID = NSXPCConnection.current().map(ObjectIdentifier.init)
    DispatchQueue.main.async { [self] in
      guard let ownerID, connections.contains(ownerID),
            let (context, client) = currentContext(), context.applicationPID == applicationPID else {
        response.call((nil, nil))
        return
      }
      ticketOwner = ownerID
      let token = ticket.capture(context, now: ProcessInfo.processInfo.systemUptime)
      response.call((token, client.bundleIdentifier()))
    }
  }

  func commit(ticket token: String, text: String, deadline: TimeInterval, withReply reply: @escaping (Bool) -> Void) {
    let response = Reply(reply)
    let ownerID = NSXPCConnection.current().map(ObjectIdentifier.init)
    DispatchQueue.main.async { [self] in
      guard let ownerID, connections.contains(ownerID), ticketOwner == ownerID else {
        response.call(false)
        return
      }
      defer { ticket.cancel(token) }
      guard token.utf8.count <= 64, text.utf8.count <= 32_768,
            let (context, client) = currentContext(),
            VoiceInsertionPolicy.allowsAutomaticInsertion(text: text, applicationID: client.bundleIdentifier()),
            ticket.consume(token, context: context, now: ProcessInfo.processInfo.systemUptime, deadline: deadline) else {
        response.call(false)
        return
      }
      // Same native insertion route as keyboard candidates. No pasteboard or synthetic keys.
      client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
      response.call(true)
    }
  }

  func cancel(ticket token: String) {
    let ownerID = NSXPCConnection.current().map(ObjectIdentifier.init)
    DispatchQueue.main.async { [self] in
      if ownerID != nil, ticketOwner == ownerID { ticket.cancel(token) }
    }
  }

  private func currentContext() -> (VoiceCommitTicket.Context, IMKTextInput)? {
    guard let client = controller?.voiceClient,
          let app = NSWorkspace.shared.frontmostApplication,
          app.bundleIdentifier == client.bundleIdentifier() else { return nil }
    let context = VoiceCommitTicket.Context(activation: activation, applicationPID: app.processIdentifier,
                                           selection: client.selectedRange())
    return (context, client)
  }

  private func publish() {
    guard publisher == nil, controller != nil, publishAttempts < 3 else { return }
    publishAttempts += 1
    let connection = NSXPCConnection(machServiceName: ROTYPE_TRANSLATION_SERVICE_NAME)
    connection.setCodeSigningRequirement(Self.requirement("im.roarkai.inputmethod.Luoke.translation"))
    connection.remoteObjectInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
    let publicationID = UUID()
    publication = publicationID
    let interrupted: @Sendable () -> Void = { [weak self] in
      guard let owner = self else { return }
      DispatchQueue.main.async {
        guard owner.publication == publicationID, let previous = owner.publisher else { return }
        owner.publisher = nil
        previous.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { owner.publish() }
      }
    }
    connection.interruptionHandler = interrupted
    connection.invalidationHandler = interrupted
    publisher = connection
    connection.resume()
    let proxy = connection.remoteObjectProxyWithErrorHandler { _ in interrupted() } as? RoTypeTranslationXPCProtocol
    proxy?.registerDictationEndpoint?(listener.endpoint)
  }

  private func ensureSettingsHelper() {
    let identifier = "im.roarkai.inputmethod.Luoke.helper"
    guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
          Date().timeIntervalSince(lastHelperLaunch) > 5 else { return }
    lastHelperLaunch = Date()
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/洛克输入法设置.app")
    DispatchQueue.global(qos: .utility).async {
      var code: SecStaticCode?
      var requirement: SecRequirement?
      guard SecStaticCodeCreateWithPath(helper as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(Self.requirement(identifier) as CFString, [], &requirement) == errSecSuccess,
            let requirement, SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return }
      DispatchQueue.main.async {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
      }
    }
  }

  private static func requirement(_ identifier: String) -> String {
    "anchor apple generic and certificate leaf[subject.OU] = \"DF7J2VBQD8\" and identifier \"\(identifier)\""
  }
}
