import AppKit
import Carbon
@preconcurrency import ApplicationServices
import AVFoundation
import Combine
import RoTypeCore

@MainActor
final class VoiceInputController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = VoiceInputController()
    let models = VoiceModelStore()
    let activation = VoiceActivation()
    private var modelObservation: AnyCancellable?
    @Published private(set) var enabled = false
    @Published private(set) var status = "待机，选中洛克后自动准备"
    @Published private(set) var lastResult = ""
    @Published private(set) var lastResultInserted = false
    @Published var model: VoiceModel {
        didSet {
            guard model != oldValue else { return }
            pauseForModelMaintenance()
            models.select(model)
            UserDefaults.standard.set(model.rawValue, forKey: "voice.model")
            reconcileActivation()
        }
    }
    private let shortcut = VoiceFnShortcut()
    private let worker = VoiceWorkerClient()
    private let hud = VoiceHUD()
    private var session = VoiceSession()
    private var pendingTranscription = VoicePendingTranscription()
    private let delivery = VoiceDelivery()
    private var recorder: AVAudioRecorder?
    private var audioDirectory: URL?
    private var preparation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var timer: Timer?
    private var observations: [NSObjectProtocol] = []
    private var generation = UUID()
    private var audibleTicks = 0
    private var recordedDuration: TimeInterval = 0
    private var targetCheck: Task<Void, Never>?
    private var lastTargetCheck = Date.distantPast
    private var idleSince = Date()

    private override init() {
        model = VoiceModel(rawValue: UserDefaults.standard.string(forKey: "voice.model") ?? "") ?? .small
        super.init()
        models.select(model)
        modelObservation = models.$progress.sink { [weak self] progress in
            guard progress == nil else { return }
            Task { @MainActor in self?.reconcileActivation() }
        }
        shortcut.onPress = { [weak self] in self?.begin() }
        shortcut.onRelease = { [weak self] in self?.finishRecording() }
        shortcut.onCancel = { [weak self] in self?.cancel() }
        shortcut.onInteraction = { [weak self] in
            self?.session.invalidateTarget()
            self?.delivery.cancel()
        }
        shortcut.sessionActive = { [weak self] in
            guard let self else { return false }
            return self.session.state != .idle || self.delivery.isPending
        }
        worker.onReply = { [weak self] in self?.receive($0) }
        hud.onCopy = { [weak self] in self?.copyResult() }
        hud.onCancel = { [weak self] in self?.cancel(); self?.hud.hide() }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.didWakeNotification] {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                let sleeping = notification.name == NSWorkspace.willSleepNotification
                Task { @MainActor in
                    if sleeping {
                        self?.cancel()
                        self?.worker.stop()
                    } else {
                        self?.session.invalidateTarget()
                        self?.delivery.cancel()
                        self?.activation.refresh()
                    }
                }
            }
            observations.append(observer)
        }
    }

    func restore() {
        activation.start { [weak self] in self?.reconcileActivation() }
    }

    func setEnabled(_ value: Bool, requestPermissions: Bool = true) {
        activation.setRequested(value)
        setRunning(value, requestPermissions: requestPermissions)
    }

    func pauseForModelMaintenance() { setRunning(false, requestPermissions: false) }

    private func reconcileActivation() {
        guard activation.isObserving, activation.requested, VoiceFnShortcut.isLuokeSelected(),
              models.progress == nil else { return }
        guard models.isPresent(model) else { status = "请下载所选模型；完成后自动准备。"; return }
        if !enabled { setRunning(true, requestPermissions: false) } else if !worker.running { prepareWorker() }
    }

    private func setRunning(_ value: Bool, requestPermissions: Bool) {
        generation = UUID()
        preparation?.cancel()
        preparation = nil
        cancel()
        shortcut.stop()
        worker.stop()
        timer?.invalidate()
        timer = nil
        enabled = false
        guard value else {
            status = activation.requested ? "待机，选中洛克后自动准备" : "自动准备已关闭"
            hud.hide()
            return
        }
        guard models.isPresent(model) else { status = "请先下载语音模型"; return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: requestPermissions] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { status = "请允许辅助功能权限，返回后自动准备"; return }
        enabled = true
        let id = generation
        preparation = Task {
            var authorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            if requestPermissions, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                authorized = await AVCaptureDevice.requestAccess(for: .audio)
            }
            guard !Task.isCancelled, generation == id else { return }
            guard authorized else { enabled = false; status = VoicePermissions.status; return }
            guard shortcut.start() else { enabled = false; status = "无法监听 Fn，请检查辅助功能权限"; return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            preparation = nil
            prepareWorker()
        }
    }

    func refreshPermissionStatus() {
        if !enabled, models.isPresent(model) { status = VoicePermissions.status }
        reconcileActivation()
    }

    func requestMicrophonePermission() {
        Task { @MainActor [weak self] in
            await VoicePermissions.requestMicrophone()
            self?.refreshPermissionStatus()
        }
    }

    private func prepareWorker() {
        guard enabled, preparation == nil, !worker.running else { return }
        status = "正在校验并加载本地模型…"
        let id = generation
        let selected = model
        preparation = Task {
            do {
                try await models.validate(selected)
                guard !Task.isCancelled, generation == id else { return }
                try worker.start(modelDirectory: models.directory(for: selected))
                armDeadline(seconds: 90)
            } catch {
                guard !Task.isCancelled, generation == id else { return }
                failed("本地模型或识别进程加载失败：\(error.localizedDescription)")
            }
            if generation == id { preparation = nil }
        }
    }

}

extension VoiceInputController {
    private func begin() {
        guard enabled, session.state == .idle, !delivery.isPending else { return }
        if !worker.ready { prepareWorker() }
        guard let id = session.begin() else { return }
        status = "正在准备录音…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let captured = await self.delivery.prepare()
            guard self.enabled, self.session.state == .recording(id) else { return }
            guard captured, !IsSecureEventInputEnabled() else {
                self.cancel()
                self.hud.show(.notice(title: "此处不能录音", detail: "当前目标为受保护的输入框、没有前台应用，或录音准备已取消。"))
                return
            }
            self.startRecording()
        }
    }

    private func startRecording() {
        lastResult = ""
        audibleTicks = 0
        recordedDuration = 0
        do {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("rotype-voice-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            audioDirectory = folder
            let audio = folder.appendingPathComponent("recording.caf")
            let recorder = try AVAudioRecorder(url: audio, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            self.recorder = recorder
            guard recorder.record(forDuration: 60) else { throw CocoaError(.fileWriteUnknown) }
            status = "正在录音 · 松开 Fn 完成 · Esc 取消"
            hud.show(.recording)
        } catch {
            cancel()
            status = "无法启动麦克风，请检查系统默认输入设备"
            hud.show(.notice(title: "麦克风未启动", detail: status))
        }
    }

    private func finishRecording() {
        guard case .recording = session.state else { return }
        guard let recorder else { cancel(); return }
        let duration = max(recordedDuration, recorder.currentTime)
        let audio = recorder.url
        self.recorder = nil
        recorder.delegate = nil
        recorder.stop()
        // Coarse silence rejection only; never trim the waveform's beginning or end.
        guard duration >= 0.25, audibleTicks >= 2, let id = session.stop() else {
            cancel()
            status = "未听到有效录音，请重新按住 Fn"
            hud.show(.notice(title: "未听到语音", detail: status), dismissAfter: 3)
            return
        }
        pendingTranscription.enqueue(id: id, audio: audio)
        if worker.ready {
            submitPendingTranscription()
        } else {
            status = "录音已结束，正在等待本地模型… · Esc 取消"
            hud.show(.preparing)
            armDeadline(seconds: 90)
            prepareWorker()
        }
    }

    func cancel() {
        if case .recognizing = session.state { worker.stop() }
        if worker.running, !worker.ready { worker.stop() }
        session.cancel()
        pendingTranscription.cancel()
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        deadline?.cancel()
        deadline = nil
        delivery.cancel()
        removeAudio()
        idleSince = Date()
        status = enabled ? "已取消 · 按住 Fn 重新开始" : "语音未开启"
        hud.hide()
    }

    func copyResult() {
        guard !lastResult.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastResult, forType: .string)
        hud.show(.success("已复制 · 请自行粘贴"), dismissAfter: 2)
    }

    func shutdown() {
        activation.stop()
        modelObservation = nil
        generation = UUID()
        preparation?.cancel()
        cancel()
        shortcut.stop()
        worker.stop()
        timer?.invalidate()
        for observer in observations { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observations.removeAll()
    }

    private func receive(_ reply: VoiceWorkerClient.Reply) {
        if reply.event == "ready" {
            deadline?.cancel()
            if session.state == .idle {
                status = "就绪 · 选中洛克后按住 Fn 说话"
                idleSince = Date()
            }
            submitPendingTranscription()
            return
        }
        if reply.event == "error" { failed(reply.failure ?? "识别进程未能完成本次请求。"); return }
        guard reply.event == "result", let id = reply.id,
              let shouldDeliver = session.takeResult(id: id) else { return }
        deadline?.cancel()
        removeAudio()
        idleSince = Date()
        let text = (reply.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 32_768 else { failed(); return }
        lastResult = text
        lastResultInserted = false
        delivery.finish(VoiceInsertionPolicy.singleLineText(text), allowed: shouldDeliver) { [weak self] inserted in
            guard let self else { return }
            self.lastResultInserted = inserted
            self.status = inserted ? "已填入 · 未发送" : (self.delivery.failureReason ?? "未能填入，文字已保留")
            self.hud.show(inserted ? .success(self.status) : .result(text, reason: self.status),
                          dismissAfter: inserted ? 1 : nil)
        }
    }

    private func submitPendingTranscription() {
        guard let request = pendingTranscription.take(ready: worker.ready),
              session.state == .recognizing(request.id) else { return }
        status = "本地识别中… · Esc 取消"
        hud.show(.processing)
        do {
            try worker.transcribe(id: request.id, audio: request.audio)
            armDeadline(seconds: 45)
        } catch { failed("无法提交本次录音：\(error.localizedDescription)") }
    }

    private func failed(_ detail: String = "本地识别未完成，请重新录音。") {
        cancel()
        worker.stop()
        status = "本地识别未成功，请重新按住 Fn 准备模型"
        hud.show(.notice(title: "识别未完成", detail: detail + "\n原录音未保留，不能恢复重试。"))
    }

    private func armDeadline(seconds: Double) {
        deadline?.cancel()
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.failed(seconds == 90 ? "等待本地模型超时（90 秒）。" : "本地识别超时（45 秒）。")
        }
    }

    private func tick() {
        if session.state != .idle, IsSecureEventInputEnabled() { cancel(); return }
        if session.state != .idle, targetCheck == nil,
           Date().timeIntervalSince(lastTargetCheck) > 0.5 {
            lastTargetCheck = Date()
            let state = session.state
            targetCheck = Task { @MainActor [weak self] in
                guard let self else { return }
                let valid = await self.delivery.targetIsCurrent()
                if self.session.state == state, !valid {
                    self.session.invalidateTarget()
                    self.delivery.cancel()
                }
                self.targetCheck = nil
            }
        }
        if case .recording = session.state, let recorder {
            recordedDuration = max(recordedDuration, recorder.currentTime)
            recorder.updateMeters()
            hud.updateRecording(elapsed: recordedDuration, decibels: recorder.averagePower(forChannel: 0))
            if recorder.averagePower(forChannel: 0) > -55 { audibleTicks += 1 }
            if shortcut.shouldFinishRecording(elapsed: recordedDuration, recorderIsRunning: recorder.isRecording) {
                finishRecording()
            }
        }
        if session.state == .idle, worker.ready, Date().timeIntervalSince(idleSince) > 300 {
            worker.stop()
            status = "模型已休眠 · 下次 Fn 将重新准备"
        }
    }

    private func removeAudio() {
        if let audioDirectory { try? FileManager.default.removeItem(at: audioDirectory) }
        audioDirectory = nil
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identifier else { return }
            self.failed()
        }
    }
}
