import Foundation

struct RoTypeTranslationResult {
  let generation: Int64
  let direction: String
  let sourceText: String
  let translatedText: String
}

final class RoTypeTranslationClient: @unchecked Sendable {
  private final class WeakReference: @unchecked Sendable {
    weak var value: RoTypeTranslationClient?

    init(_ value: RoTypeTranslationClient) {
      self.value = value
    }
  }

  typealias Completion = (Result<RoTypeTranslationResult, Error>) -> Void

  private struct Pending {
    let generation: Int64
    let completion: Completion
    let timeout: DispatchWorkItem
  }

  private var connection: NSXPCConnection?
  private var pending: [String: Pending] = [:]

  func translate(
    sessionID: String,
    generation: Int64,
    request: CandidateTranslationRequest,
    completion: @escaping Completion
  ) {
    assertMainQueue()
    cancel(sessionID: sessionID, throughGeneration: generation - 1)

    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.pending[sessionID]?.generation == generation else { return }
      self.pending[sessionID] = nil
      self.cancellationProxy()?.cancel(sessionID: sessionID, throughGeneration: generation)
      completion(.failure(CandidateTranslationFailure.timedOut))
    }
    pending[sessionID] = Pending(generation: generation, completion: completion, timeout: timeout)
    DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)

    guard let proxy = proxy(errorHandler: { [weak self] error in
      DispatchQueue.main.async { self?.finish(sessionID: sessionID, generation: generation, result: .failure(error)) }
    }) else {
      finish(sessionID: sessionID, generation: generation, result: .failure(CandidateTranslationFailure.serviceUnavailable))
      return
    }

    let weakClient = WeakReference(self)
    proxy.translateCandidate(
      sessionID: sessionID,
      generation: generation,
      request: request.payload
    ) { returnedGeneration, direction, returnedSource, translatedText, error in
      DispatchQueue.main.async {
        guard let self = weakClient.value else { return }
        if let error {
          self.finish(sessionID: sessionID, generation: generation, result: .failure(error))
          return
        }
        guard returnedGeneration == generation,
              let direction, let returnedSource, let translatedText,
              request.accepts(source: returnedSource, direction: direction) else {
          self.finish(
            sessionID: sessionID,
            generation: generation,
            result: .failure(CandidateTranslationFailure.invalidResponse)
          )
          return
        }
        self.finish(
          sessionID: sessionID,
          generation: returnedGeneration,
          result: .success(.init(
            generation: returnedGeneration,
            direction: direction,
            sourceText: returnedSource,
            translatedText: translatedText
          ))
        )
      }
    }
  }

  func recordControllerInput() {
    assertMainQueue()
    proxy()?.recordControllerInput()
  }

  func cancel(sessionID: String, throughGeneration: Int64) {
    assertMainQueue()
    if let request = pending[sessionID], request.generation <= throughGeneration {
      request.timeout.cancel()
      pending[sessionID] = nil
    }
    cancellationProxy()?.cancel(sessionID: sessionID, throughGeneration: throughGeneration)
  }

  func invalidate() {
    assertMainQueue()
    failAllPending(with: CandidateTranslationFailure.cancelled)
    connection?.invalidationHandler = nil
    connection?.interruptionHandler = nil
    connection?.invalidate()
    connection = nil
  }

  private func proxy(errorHandler: ((Error) -> Void)? = nil) -> RoTypeTranslationXPCProtocol? {
    let connection = connection ?? makeConnection()
    return connection.remoteObjectProxyWithErrorHandler { error in
      errorHandler?(error)
    } as? RoTypeTranslationXPCProtocol
  }

  private func makeConnection() -> NSXPCConnection {
    let connection = NSXPCConnection(machServiceName: ROTYPE_TRANSLATION_SERVICE_NAME, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
    connection.interruptionHandler = { [weak self] in
      DispatchQueue.main.async { self?.connectionInterrupted(connection) }
    }
    connection.invalidationHandler = { [weak self] in
      DispatchQueue.main.async { self?.connectionInvalidated(connection) }
    }
    connection.resume()
    self.connection = connection
    return connection
  }

  private func cancellationProxy() -> RoTypeTranslationXPCProtocol? {
    guard let connection else { return nil }
    return connection.remoteObjectProxyWithErrorHandler { _ in } as? RoTypeTranslationXPCProtocol
  }

  private func connectionInterrupted(_ interrupted: NSXPCConnection) {
    guard connection === interrupted else { return }
    connection = nil
    failAllPending(with: CandidateTranslationFailure.serviceUnavailable)
  }

  private func connectionInvalidated(_ invalidated: NSXPCConnection) {
    guard connection === invalidated else { return }
    connection = nil
    failAllPending(with: CandidateTranslationFailure.serviceUnavailable)
  }

  private func failAllPending(with error: Error) {
    let requests = Array(pending.values)
    pending.removeAll()
    for request in requests {
      request.timeout.cancel()
      request.completion(.failure(error))
    }
  }

  private func finish(
    sessionID: String,
    generation: Int64,
    result: Result<RoTypeTranslationResult, Error>
  ) {
    assertMainQueue()
    guard let request = pending[sessionID], request.generation == generation else { return }
    request.timeout.cancel()
    pending[sessionID] = nil
    request.completion(result)
  }

  private func assertMainQueue() {
    dispatchPrecondition(condition: .onQueue(.main))
  }

}
