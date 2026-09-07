import AppKit
@preconcurrency import ApplicationServices
import AVFoundation

@MainActor
enum VoicePermissions {
    enum Authorization: Equatable {
        case granted, notRequested, denied, restricted, unknown
        var title: String {
            switch self {
            case .granted: "已授权"
            case .notRequested: "待授权"
            case .denied: "未授权"
            case .restricted: "系统限制"
            case .unknown: "无法读取"
            }
        }
    }

    struct Snapshot: Equatable {
        let microphone: Authorization
        let accessibility: Authorization
    }

    static func microphoneAuthorization(_ value: AVAuthorizationStatus) -> Authorization {
        switch value {
        case .authorized: .granted
        case .notDetermined: .notRequested
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }

    static func snapshot() -> Snapshot {
        Snapshot(microphone: microphoneAuthorization(AVCaptureDevice.authorizationStatus(for: .audio)),
                 accessibility: AXIsProcessTrusted() ? .granted : .denied)
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static var status: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            AXIsProcessTrusted() ? "权限已就绪，选中洛克后自动准备" : "请允许「洛克输入法设置」的辅助功能权限"
        case .notDetermined: "请在下方「麦克风」一栏点击「去授权」"
        case .denied: "请在麦克风列表中允许「洛克输入法」，不是旧的「洛克语音输入」"
        case .restricted: "麦克风访问被系统策略限制"
        @unknown default: "无法确定麦克风权限状态"
        }
    }

    static func requestMicrophone() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
