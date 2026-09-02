import Foundation
import WhisperKit

public actor WhisperTranscriber {
    public static let defaultModel = "openai_whisper-base"

    private var whisperKit: WhisperKit?
    private let modelStore: WhisperModelStore

    public init(modelStore: WhisperModelStore = WhisperModelStore()) {
        self.modelStore = modelStore
    }

    public func transcribe(audioAt url: URL) async throws -> String {
        let kit: WhisperKit
        if let whisperKit {
            kit = whisperKit
        } else {
            let loaded = try await loadModel()
            whisperKit = loaded
            kit = loaded
        }

        let results = try await kit.transcribe(audioPath: url.path)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadModel() async throws -> WhisperKit {
        if let localModelFolder = modelStore.existingModelFolder() {
            do {
                return try await WhisperKit(
                    modelFolder: localModelFolder.path,
                    load: true,
                    download: false
                )
            } catch {
                try modelStore.invalidate(modelFolder: localModelFolder)
            }
        }

        try modelStore.prepare()
        let loaded = try await WhisperKit(
            model: Self.defaultModel,
            downloadBase: modelStore.rootDirectory,
            prewarm: false,
            load: true,
            download: true
        )
        guard let modelFolder = loaded.modelFolder else {
            throw WhisperModelStoreError.modelFolderMissing
        }
        try modelStore.save(modelFolder: modelFolder)
        return loaded
    }
}
