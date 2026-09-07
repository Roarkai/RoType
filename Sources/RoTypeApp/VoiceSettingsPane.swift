import AppKit
import RoTypeCore
import SwiftUI

struct VoiceSettingsPane: View {
    @ObservedObject private var voice = VoiceInputController.shared
    @ObservedObject private var models = VoiceInputController.shared.models
    @ObservedObject private var activation = VoiceInputController.shared.activation

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PaneTitle("本地语音", detail: "选中洛克后自动准备。按住 Fn 说话，松开识别并填入。")
            SettingsCard {
                HStack(spacing: 16) {
                    SettingsGroupTitle(title: "随输入法自动准备", detail: "记住此开关；加载模型不会开启麦克风。")
                    Spacer(minLength: 8)
                    SettingsBadge(text: activation.requested ? "自动" : "关闭")
                    Toggle("自动准备 Fn 语音", isOn: Binding(
                        get: { activation.requested }, set: { voice.setEnabled($0) }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .tint(CossStyle.text)
                    .accessibilityLabel("随输入法自动准备语音")
                }
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform").foregroundStyle(CossStyle.muted)
                    Text(activation.requested ? voice.status : "自动准备已关闭，可随时重新打开。")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                Text("按住 Fn 录音 · 松开结束 · Esc 取消 · 单次最长 60 秒")
                    .font(.system(size: 11)).foregroundStyle(CossStyle.muted)
            }
            SettingsCard {
                HStack {
                    SettingsGroupTitle(title: "识别模型", detail: "两个模型都在本机运行，切换不会删除已下载文件。")
                    Spacer()
                    SettingsBadge(text: models.isPresent(voice.model) ? "已下载" : "待下载")
                }
                Picker("识别模型", selection: $voice.model) {
                    Text("0.6B · 快速").tag(VoiceModel.small)
                    Text("1.7B · 增强").tag(VoiceModel.large)
                }
                .pickerStyle(.segmented).labelsHidden()
                .disabled(models.progress != nil)
                if let progress = models.progress {
                    ProgressView(value: progress).tint(CossStyle.text)
                    HStack {
                        Text(models.transferDetail).font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(CossStyle.muted)
                        Spacer()
                        Button("取消下载") { models.cancel() }
                    }
                } else {
                    HStack {
                        Text(models.message).font(.system(size: 12)).foregroundStyle(CossStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button(models.isPresent(voice.model) ? "校验 / 修复" : "下载模型") {
                            voice.pauseForModelMaintenance()
                            models.download(voice.model)
                        }
                    }
                }
                Text("切换或校验会结束录音；损坏文件会重新下载。自动准备开关保持不变。")
                    .font(.system(size: 11)).foregroundStyle(CossStyle.muted)
            }
            VoicePermissionsPane()
            if !voice.lastResult.isEmpty {
                SettingsCard {
                    HStack {
                        SettingsGroupTitle(title: "最近一次结果", detail: voice.lastResultInserted
                            ? "已自动填入。此处仅保留备份，无需再复制。" : "文字已保留；未能填入的原因见状态提示。")
                        Spacer()
                        Button("复制备份") { voice.copyResult() }
                    }
                    Text(voice.lastResult).font(.system(size: 13)).textSelection(.enabled)
                }
            }
            Text("向有效输入框直接填入，终端也支持。识别中的换行转为空格，不触发回车；目标变化或连接不可用时才保留结果。模型空闲 5 分钟后释放。")
                .font(.system(size: 11)).foregroundStyle(CossStyle.muted)
        }
        .onAppear { voice.refreshPermissionStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            voice.refreshPermissionStatus()
        }
    }

}
