import SwiftUI

struct PrivacyPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle("隐私与诊断", detail: "仅保留键盘输入与本地翻译。")
            SettingsCard {
                FeatureRow(
                    icon: "mic.slash",
                    title: "输入法不使用麦克风",
                    detail: "不包含录音、语音识别或语音后台服务"
                )
                Divider()
                FeatureRow(
                    icon: "keyboard.badge.ellipsis",
                    title: "输入法不监听全局按键",
                    detail: "仅通过 macOS InputMethodKit 处理当前输入会话"
                )
                Divider()
                FeatureRow(
                    icon: "lock.fill",
                    title: "本地翻译链路",
                    detail: "输入法通过受签名角色授权的 XPC 发送请求；Secure Input 启用时不发送内容或写入响应缓存"
                )
                Divider()
                FeatureRow(
                    icon: "externaldrive.badge.checkmark",
                    title: "Apple 本地翻译",
                    detail: "原文和译文在设备上处理；Apple 可能收集不含原文和译文的 API 使用与性能元数据"
                )
            }
        }
    }
}
