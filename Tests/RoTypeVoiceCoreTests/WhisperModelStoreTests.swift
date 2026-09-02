import Foundation
import Testing
@testable import RoTypeVoiceCore

@Test func persistsAndReopensExistingModelFolder() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-model-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = WhisperModelStore(rootDirectory: root)
    let modelFolder = root.appendingPathComponent("openai_whisper-base", isDirectory: true)
    try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

    try store.save(modelFolder: modelFolder)

    #expect(store.existingModelFolder() == modelFolder.standardizedFileURL)
}

@Test func ignoresMissingPersistedModelFolder() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-model-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = WhisperModelStore(rootDirectory: root)
    let modelFolder = root.appendingPathComponent("openai_whisper-base", isDirectory: true)
    try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
    try store.save(modelFolder: modelFolder)
    try FileManager.default.removeItem(at: modelFolder)

    #expect(store.existingModelFolder() == nil)
}

@Test func rejectsModelFolderOutsideManagedRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-model-store-\(UUID().uuidString)", isDirectory: true)
    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-outside-model-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

    let store = WhisperModelStore(rootDirectory: root)

    #expect(throws: WhisperModelStoreError.self) {
        try store.save(modelFolder: outside)
    }
}

@Test func invalidatesManagedModelFolderAndPointer() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-model-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = WhisperModelStore(rootDirectory: root)
    let modelFolder = root.appendingPathComponent("openai_whisper-base", isDirectory: true)
    try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
    try store.save(modelFolder: modelFolder)

    try store.invalidate(modelFolder: modelFolder)

    #expect(!FileManager.default.fileExists(atPath: modelFolder.path))
    #expect(store.existingModelFolder() == nil)
}

@Test func rejectsInvalidationOutsideManagedRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-model-store-\(UUID().uuidString)", isDirectory: true)
    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-outside-model-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

    let store = WhisperModelStore(rootDirectory: root)

    #expect(throws: WhisperModelStoreError.self) {
        try store.invalidate(modelFolder: outside)
    }
    #expect(FileManager.default.fileExists(atPath: outside.path))
}

@Test func rejectsInvalidationThroughSymlinkedManagedPath() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("rotype-symlink-model-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let root = base.appendingPathComponent("managed", isDirectory: true)
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    let outsideModel = outside.appendingPathComponent("model", isDirectory: true)
    let sentinel = outsideModel.appendingPathComponent("keep.txt")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideModel, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: sentinel)

    let link = root.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    let linkedModel = link.appendingPathComponent("model", isDirectory: true)
    let pointerFile = root.appendingPathComponent("active-model-path.txt")
    try Data(linkedModel.path.utf8).write(to: pointerFile)

    let store = WhisperModelStore(rootDirectory: root)

    #expect(store.existingModelFolder() == nil)
    #expect(throws: WhisperModelStoreError.self) {
        try store.invalidate(modelFolder: linkedModel)
    }
    #expect(FileManager.default.fileExists(atPath: sentinel.path))
}
