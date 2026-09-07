import Foundation
import Combine
import RoTypeCore

@MainActor
final class VoiceModelStore: ObservableObject {
    @Published private(set) var progress: Double?
    @Published private(set) var message = "点击下载后获取模型；主站失败自动尝试 hf-mirror.com，文件均校验 SHA-256。"
    @Published private(set) var transferDetail = ""
    private var task: Task<Void, Never>?
    private var generation = UUID()
    let root: URL

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RoType/VoiceModels", isDirectory: true)) {
        self.root = root
    }

    func directory(for model: VoiceModel) -> URL { root.appendingPathComponent(model.rawValue, isDirectory: true) }

    func isPresent(_ model: VoiceModel) -> Bool {
        model.files.allSatisfy {
            let url = directory(for: model).appendingPathComponent($0.name)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return Int64(size ?? -1) == $0.bytes
        }
    }

    func validate(_ model: VoiceModel) async throws {
        let folder = directory(for: model)
        try await Task.detached(priority: .utility) {
            for file in model.files { try file.validate(at: folder.appendingPathComponent(file.name)) }
        }.value
        try Task.checkCancellation()
    }

    func select(_ model: VoiceModel) {
        if task != nil { cancel() }
        generation = UUID()
        transferDetail = ""
        progress = nil
        message = isPresent(model)
            ? "已检测到 \(model.title) 模型，开启语音时会校验。"
            : "点击下载后获取模型；主站失败自动尝试 hf-mirror.com，文件均校验 SHA-256。"
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        progress = nil
        message = "下载已取消；已完成的分块保留，点击下载可继续。"
    }

    func download(_ model: VoiceModel) {
        guard task == nil else { return }
        let id = UUID()
        generation = id
        progress = 0
        transferDetail = "正在检查已下载的文件…"
        message = "正在下载 \(model.title)"
        task = Task {
            do {
                try await transfer(model, id: id)
                try Task.checkCancellation()
                message = "模型下载完成，SHA-256 校验通过。可以开启语音输入。"
                transferDetail = ""
            } catch {
                guard generation == id else { return }
                message = "下载中断（\((error as NSError).code)）；已保留断点，点击下载继续。"
            }
            guard generation == id else { return }
            progress = nil
            task = nil
        }
    }

    private func transfer(_ model: VoiceModel, id: UUID) async throws {
        let folder = directory(for: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let total = model.files.reduce(Int64(0)) { $0 + $1.bytes }
        var completed: Int64 = 0
        for file in model.files {
            try Task.checkCancellation()
            let destination = folder.appendingPathComponent(file.name)
            let valid = await Task.detached(priority: .utility) {
                (try? file.validate(at: destination)) != nil
            }.value
            if !valid {
                let before = completed
                let urls = ["huggingface.co", "hf-mirror.com"].compactMap {
                    URL(string: "https://\($0)/\(model.repository)/resolve/\(model.revision)/\(file.name)")
                }
                try await VoiceFileDownloader().download(file, from: urls, to: destination) { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.generation == id, self.progress != nil else { return }
                        self.update(event, file: file, completed: before, total: total)
                    }
                }
            }
            completed += file.bytes
        }
    }

    private func update(_ event: VoiceFileDownloader.Event, file: VoiceModelFile, completed: Int64, total: Int64) {
        switch event {
        case .transferring(let bytes, let source):
            progress = min(1, Double(completed + bytes) / Double(total))
            let received = ByteCountFormatter.string(fromByteCount: completed + bytes, countStyle: .file)
            let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            transferDetail = "\(received) / \(size) · \(source)"
            message = "正在下载 \(file.name) · 连接超时会自动重试"
        case .retrying(let source, let code):
            message = "\(source) 连接失败（\(code)），正在重试 / 切换来源…"
        case .verifying:
            message = "正在校验 \(file.name)，请稍候…"
        }
    }
}
