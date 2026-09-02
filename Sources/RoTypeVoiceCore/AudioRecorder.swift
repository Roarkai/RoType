@preconcurrency import AVFoundation
import Foundation

public enum AudioRecordingError: LocalizedError {
    case microphonePermissionDenied
    case recordingFailed

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "需要在系统设置 → 隐私与安全性 → 麦克风中允许 RoType Voice。"
        case .recordingFailed:
            "无法开始录音。"
        }
    }
}

@MainActor
public final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    public override init() {}

    public func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start() async throws {
        guard await requestPermission() else {
            throw AudioRecordingError.microphonePermissionDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotype-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AudioRecordingError.recordingFailed
        }

        self.recorder = recorder
        currentURL = url
    }

    public func stop() throws -> URL {
        guard let recorder, let currentURL else {
            throw AudioRecordingError.recordingFailed
        }

        recorder.stop()
        self.recorder = nil
        self.currentURL = nil
        return currentURL
    }
}
