import Foundation
import Security

@MainActor
final class VoiceWorkerClient {
    struct Reply: Decodable, Sendable {
        let event: String
        let id: UUID?
        let text: String?
        var failure: String?
    }

    var onReply: ((Reply) -> Void)?
    private(set) var ready = false
    var running: Bool { process?.isRunning == true }
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()

    func start(modelDirectory: URL) throws {
        stop()
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/RoTypeVoiceWorker")
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"DF7J2VBQD8\""
            + " and identifier \"im.roarkai.inputmethod.Luoke.asr\""
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            throw CocoaError(.executableNotLoadable)
        }
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = executable
        child.arguments = [modelDirectory.path]
        child.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "TMPDIR": NSTemporaryDirectory(),
                             "HF_HUB_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1"]
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        output?.readabilityHandler = { [weak self, weak child] handle in
            let data = Self.readOutput(handle)
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in
                guard let self, let child, self.process === child else { return }
                self.consume(data)
            }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in
                guard let self, self.process === child else { return }
                self.stop()
                self.onReply?(Reply(event: "error", id: nil, text: nil,
                                    failure: "识别进程退出（状态码 \(child.terminationStatus)）。"))
            }
        }
        do { try child.run() } catch { stop(); throw error }
    }

    func transcribe(id: UUID, audio: URL) throws {
        guard ready, let input else { throw CocoaError(.executableNotLoadable) }
        let payload = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "audioPath": audio.path])
        try input.write(contentsOf: payload + Data([10]))
    }

    func stop() {
        ready = false
        output?.readabilityHandler = nil
        try? input?.close()
        input = nil
        // The active callback retains its handle; release ownership instead of
        // closing a descriptor concurrently with availableData.
        output = nil
        buffer.removeAll()
        let child = process
        process = nil
        child?.terminationHandler = nil
        guard let child, child.isRunning else { return }
        child.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    nonisolated static func readOutput(_ handle: FileHandle) -> Data {
        // read(upToCount:) can wait for the requested length on a pipe.
        // Ready/result messages are short and the worker intentionally stays alive.
        handle.availableData
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 512 * 1024 else {
            stop()
            onReply?(Reply(event: "error", id: nil, text: nil, failure: "识别进程返回的数据超过限制。"))
            return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            let prefix = Data("ROTYPE_VOICE:".utf8)
            let reply = line.starts(with: prefix)
                ? try? JSONDecoder().decode(Reply.self, from: line.dropFirst(prefix.count)) : nil
            buffer.removeSubrange(...newline)
            guard let reply else { continue }
            if reply.event == "ready" { ready = true }
            onReply?(reply)
        }
    }
}
