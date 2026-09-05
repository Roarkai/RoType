import Foundation
import RoTypeXPCProtocol

@MainActor
final class ControllerInputVerificationClient {
    typealias Completion = @MainActor @Sendable (Result<Int64, Error>) -> Void

    private var connection: NSXPCConnection?
    private var connectionGeneration = 0

    func currentGeneration(completion: @escaping Completion) {
        let connection = connection ?? makeConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler(
            Self.proxyErrorHandler(completion: completion)
        ) as? RoTypeTranslationXPCProtocol else {
            completion(.failure(Self.error("Controller verification service is unavailable.")))
            return
        }

        proxy.controllerInputGeneration(reply: Self.generationReply(completion: completion))
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: ROTYPE_TRANSLATION_SERVICE_NAME)
        connectionGeneration &+= 1
        let generation = connectionGeneration
        connection.remoteObjectInterface = NSXPCInterface(with: RoTypeTranslationXPCProtocol.self)
        connection.interruptionHandler = Self.disconnectionHandler(client: self, generation: generation)
        connection.invalidationHandler = Self.disconnectionHandler(client: self, generation: generation)
        connection.resume()
        self.connection = connection
        return connection
    }

    nonisolated private static func proxyErrorHandler(
        completion: @escaping Completion
    ) -> @Sendable (Error) -> Void {
        { error in
            Task { @MainActor in completion(.failure(error)) }
        }
    }

    nonisolated private static func generationReply(
        completion: @escaping Completion
    ) -> @Sendable (Int64, Error?) -> Void {
        { generation, error in
            Task { @MainActor in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(generation))
                }
            }
        }
    }

    nonisolated private static func disconnectionHandler(
        client: ControllerInputVerificationClient,
        generation: Int
    ) -> @Sendable () -> Void {
        { [weak client] in
            Task { @MainActor in client?.discard(generation: generation) }
        }
    }

    private func discard(generation: Int) {
        guard connectionGeneration == generation else { return }
        connection = nil
    }

    private static func error(_ description: String) -> NSError {
        NSError(
            domain: ROTYPE_TRANSLATION_SERVICE_NAME,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
