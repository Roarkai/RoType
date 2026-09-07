import AppKit
import SwiftUI

struct VoicePermissionsPane: View {
    @State private var permissions: VoicePermissions.Snapshot
    private let readSnapshot: () -> VoicePermissions.Snapshot
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(readSnapshot: @escaping () -> VoicePermissions.Snapshot = { VoicePermissions.snapshot() }) {
        self.readSnapshot = readSnapshot
        _permissions = State(initialValue: readSnapshot())
    }

    var body: some View {
        SettingsCard {
            SettingsGroupTitle(title: "权限与设备", detail: "状态直接读取系统，返回此窗口时自动更新。")
            permissionRow("麦克风", owner: "洛克输入法 · 仅按住 Fn 时录音", state: permissions.microphone) {
                VoiceInputController.shared.requestMicrophonePermission()
            }
            Divider()
            permissionRow("辅助功能", owner: "洛克输入法设置 · Fn 快捷键与目标检查", state: permissions.accessibility) {
                VoicePermissions.requestAccessibility()
            }
            Divider()
            HStack {
                SettingsGroupTitle(title: "Fn 快捷键", detail: "系统 Fn 用途建议设为「不执行任何操作」。")
                Spacer()
                Button("键盘设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            DisclosureGroup("快捷键与设备说明") {
                Text("使用系统默认麦克风。关闭其他工具的 Fn 快捷键，将系统 Fn 用途设为「不执行任何操作」。洛克不会替你修改。")
                    .font(.system(size: 12)).foregroundStyle(CossStyle.muted).padding(.top, 8)
            }
            .font(.system(size: 12))
        }
        .onAppear { update() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            update()
        }
        .onReceive(refresh) { _ in if NSApp.isActive { update() } }
    }

    private func update() {
        let latest = readSnapshot()
        if latest != permissions {
            permissions = latest
            VoiceInputController.shared.refreshPermissionStatus()
        }
    }

    private func permissionRow(_ title: String, owner: String, state: VoicePermissions.Authorization,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            SettingsGroupTitle(title: title, detail: owner)
            Spacer(minLength: 4)
            Label {
                Text(state.title).foregroundStyle(CossStyle.text)
            } icon: {
                Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(state == .granted ? Color.green : Color.orange)
            }
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                .accessibilityLabel("\(title)：\(state.title)")
            Button(state == .granted ? "管理" : "去授权", action: action)
        }
    }
}
