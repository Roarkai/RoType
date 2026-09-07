import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

// Private stdin/stdout channel owned by the parent. No listener, HTTP server,
// cloud fallback or audio logging. Library diagnostic output is not protocol data.
struct Request: Decodable {
    let id: UUID
    let audioPath: String
}

struct Reply: Encodable {
    let event: String
    var id: UUID?
    var text: String?
    var failure: String?
}

func emit(_ reply: Reply) {
    guard let data = try? JSONEncoder().encode(reply) else { return }
    FileHandle.standardOutput.write(Data("ROTYPE_VOICE:".utf8) + data + Data([10]))
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let value = (MLXArray([1, 2, 3]) + 1).sum().item(Int.self)
    guard value == 9 else { exit(1) }
    emit(Reply(event: "self-test-ok"))
    exit(0)
}
guard CommandLine.arguments.count == 2 else { exit(64) }
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    // Deliberately load ONLY a local directory: inference cannot initiate downloads.
    let model = try await Qwen3ASRModel.fromModelDirectory(folder)
    emit(Reply(event: "ready"))
    while let line = readLine() {
        guard line.utf8.count < 8192,
              let request = try? JSONDecoder().decode(Request.self, from: Data(line.utf8)) else { exit(65) }
        do {
            let url = URL(fileURLWithPath: request.audioPath)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size < 4_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            let (_, audio) = try loadAudioArray(from: url, sampleRate: 16000)
            let result = model.generate(audio: audio, maxTokens: 1024, language: "Chinese", chunkDuration: 30)
            emit(Reply(event: "result", id: request.id, text: result.text))
        } catch {
            emit(Reply(event: "error", id: request.id, failure: "无法读取本次录音：\(error.localizedDescription)"))
        }
    }
} catch {
    emit(Reply(event: "error", failure: "本地模型加载失败：\(error.localizedDescription)"))
    exit(1)
}
