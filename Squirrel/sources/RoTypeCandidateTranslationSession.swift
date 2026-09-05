import Foundation

struct RoTypeCandidateSnapshot: Equatable {
  let rawInput: String
  let source: String
  // Rime segment bounds and absolute selected index; valid only for this input.
  let identity: String
  let scope: String

  var translationRequest: CandidateTranslationRequest? {
    guard let scope = CandidateTranslationRequest.Scope(rawValue: scope) else { return nil }
    return try? CandidateTranslationRequest(rawInput: rawInput, sourceText: source, identity: identity, scope: scope)
  }
}

struct RoTypeCandidateTranslationSession {
  struct Ticket: Equatable {
    let generation: Int64
    let snapshot: RoTypeCandidateSnapshot
  }
  struct Submission {
    let snapshot: RoTypeCandidateSnapshot
    let text: String
  }

  private(set) var ticket: Ticket?
  private(set) var isLoading = false
  private(set) var failure: String?
  private(set) var canRetry = false
  private(set) var direction: String?
  private var translation: String?
  private var generation: Int64 = 0

  var commit: Submission? {
    guard let ticket, let translation, !isLoading, failure == nil else { return nil }
    return Submission(snapshot: ticket.snapshot, text: translation)
  }

  mutating func observe(_ snapshot: RoTypeCandidateSnapshot) -> Ticket? {
    guard ticket?.snapshot != snapshot else { return nil }
    return begin(snapshot)
  }

  private mutating func begin(_ snapshot: RoTypeCandidateSnapshot) -> Ticket {
    invalidate()
    let request = Ticket(generation: generation, snapshot: snapshot)
    ticket = request
    isLoading = true
    return request
  }

  mutating func retry() -> Ticket? {
    guard canRetry, !isLoading, let ticket else { return nil }
    return begin(ticket.snapshot)
  }

  @discardableResult
  mutating func receive(_ text: String, for request: Ticket, direction: String? = nil) -> Bool {
    guard ticket == request, isLoading, !text.isEmpty else { return false }
    translation = text
    self.direction = direction
    isLoading = false
    failure = nil
    return true
  }

  @discardableResult
  mutating func fail(_ failure: CandidateTranslationFailure, for request: Ticket) -> Bool {
    guard ticket == request, isLoading else { return false }
    switch failure {
    case .requiresMacOS26, .languagePackMissing, .serviceUnavailable, .timedOut:
      if let candidate = request.snapshot.translationRequest, let text = candidate.staticTranslation {
        return receive(text, for: request, direction: candidate.direction.rawValue)
      }
    default:
      break // Never hide cancellation, authorization, protocol or invalid-response failures.
    }
    let message = failure == .requiresMacOS26
      ? "无匹配的静态译文；动态翻译需 macOS 26"
      : failure.message
    return fail(message, for: request, retryable: failure.canRetry)
  }

  @discardableResult
  mutating func fail(_ message: String, for request: Ticket, retryable: Bool = true) -> Bool {
    guard ticket == request, isLoading else { return false }
    canRetry = retryable
    translation = nil
    isLoading = false
    failure = message
    return true
  }

  mutating func invalidate() {
    generation += 1
    canRetry = false
    direction = nil
    ticket = nil
    translation = nil
    isLoading = false
    failure = nil
  }
}
