import Foundation
import Testing
import RoTypeCore
@testable import RoTypeApp

@MainActor
@Test func switchingVoiceModelClearsCancelledDownloadState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VoiceModelStore(root: root)
    let directory = store.directory(for: .small)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Sparse fixtures exercise presence/UI only, not the separate SHA-256 gate.
    for file in VoiceModel.small.files {
        let path = directory.appendingPathComponent(file.name)
        FileManager.default.createFile(atPath: path.path, contents: nil)
        let handle = try FileHandle(forWritingTo: path)
        try handle.truncate(atOffset: UInt64(file.bytes))
        try handle.close()
    }
    store.download(.large)
    #expect(store.progress != nil)
    store.select(.small)
    #expect(store.progress == nil)
    #expect(store.transferDetail.isEmpty)
    #expect(store.message.contains(VoiceModel.small.title))
    await Task.yield()
    #expect(store.message.contains(VoiceModel.small.title))
}
