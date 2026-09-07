import CryptoKit
import Foundation
import Testing
@testable import RoTypeCore

private final class DownloadFixture {
    let process = Process()
    let root: URL
    let base: URL
    let file: VoiceModelFile
    var destination: URL { root.appendingPathComponent("model") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let data = Data(0..<64)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        file = VoiceModelFile("model", 64, digest)
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/voice_download_server.py")
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let line = output.fileHandleForReading.availableData
        let port = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "http://127.0.0.1:\(port)") else { throw URLError(.badURL) }
        base = url
    }

    deinit {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: root)
    }
    func url(_ path: String) -> URL { base.appendingPathComponent(path) }
}

@Test func voiceDownloadFallsBackAndResumesExistingPartialFile() async throws {
    let fixture = try DownloadFixture()
    let part = fixture.destination.appendingPathExtension("part")
    try Data(0..<16).write(to: part)
    let downloader = VoiceFileDownloader(chunkBytes: 16, timeout: 1)
    try await downloader.download(fixture.file, from: [fixture.url("failed"), fixture.url("good")],
                                  to: fixture.destination) { _ in }
    try fixture.file.validate(at: fixture.destination)
    #expect(!FileManager.default.fileExists(atPath: part.path))
}

@Test func voiceDownloadTimesOutInsteadOfWaitingIndefinitely() async throws {
    let fixture = try DownloadFixture()
    let downloader = VoiceFileDownloader(chunkBytes: 64, timeout: 0.1)
    let start = Date()
    try await downloader.download(fixture.file, from: [fixture.url("slow"), fixture.url("good")],
                                  to: fixture.destination) { _ in }
    #expect(Date().timeIntervalSince(start) < 2)
    try fixture.file.validate(at: fixture.destination)
}

@Test func voiceDownloadCancellationKeepsCompletedChunksForRetry() async throws {
    let fixture = try DownloadFixture()
    let file = fixture.file
    let destination = fixture.destination
    let source = fixture.url("pause")
    let downloader = VoiceFileDownloader(chunkBytes: 16, timeout: 1)
    let task = Task {
        try await downloader.download(file, from: [source], to: destination) { _ in }
    }
    let part = destination.appendingPathExtension("part")
    var size = 0
    for _ in 0..<100 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: part.path)
        size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        if size >= 16 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(size == 16)
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    try await downloader.download(file, from: [fixture.url("good")], to: destination) { _ in }
    try file.validate(at: destination)
}

@Test func voiceDownloadRejectsWrongRangesAndCorruptedContent() async throws {
    let fixture = try DownloadFixture()
    let downloader = VoiceFileDownloader(chunkBytes: 16, timeout: 1)
    for path in ["wrong-range", "corrupt"] {
        await #expect(throws: (any Error).self) {
            try await downloader.download(fixture.file, from: [fixture.url(path)], to: fixture.destination) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
    }
}
