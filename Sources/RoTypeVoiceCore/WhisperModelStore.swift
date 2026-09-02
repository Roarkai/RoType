import Foundation

public enum WhisperModelStoreError: LocalizedError {
    case modelFolderMissing

    public var errorDescription: String? {
        "Whisper 模型下载完成后没有可用的本地模型目录。"
    }
}

public struct WhisperModelStore: Sendable {
    public let rootDirectory: URL
    private let pointerFileName = "active-model-path.txt"

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/RoType/WhisperModels", isDirectory: true)
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    public func existingModelFolder() -> URL? {
        let pointerFile = rootDirectory.appendingPathComponent(pointerFileName)
        guard
            let data = try? Data(contentsOf: pointerFile),
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            return nil
        }

        let persistedFolder = URL(fileURLWithPath: path, isDirectory: true)
        guard let folder = managedModelFolder(persistedFolder) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return folder
    }

    public func save(modelFolder: URL) throws {
        try prepare()
        guard let folder = managedModelFolder(modelFolder) else {
            throw WhisperModelStoreError.modelFolderMissing
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WhisperModelStoreError.modelFolderMissing
        }

        let pointerFile = rootDirectory.appendingPathComponent(pointerFileName)
        try Data(folder.path.utf8).write(to: pointerFile, options: .atomic)
    }

    public func invalidate(modelFolder: URL) throws {
        guard let folder = managedModelFolder(modelFolder) else {
            throw WhisperModelStoreError.modelFolderMissing
        }

        let fileManager = FileManager.default
        let pointerFile = rootDirectory.appendingPathComponent(pointerFileName)
        if fileManager.fileExists(atPath: pointerFile.path) {
            try fileManager.removeItem(at: pointerFile)
        }
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
    }

    private func managedModelFolder(_ folder: URL) -> URL? {
        let resolvedRoot = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedFolder = folder.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = resolvedRoot.pathComponents
        let folderComponents = resolvedFolder.pathComponents

        guard
            folderComponents.count > rootComponents.count,
            folderComponents.starts(with: rootComponents)
        else {
            return nil
        }
        return resolvedFolder
    }
}
