import SwiftUI

struct PrivacyPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PaneTitle("隐私与诊断", detail: "哪些数据会被处理，什么时候会访问麦克风。")
            SettingsCard {
                FeatureRow(
                    icon: "mic.slash",
                    title: "麦克风仅在主动录音时使用",
                    detail: "自动准备只加载模型，不会录音。按住 Fn 才使用麦克风；临时音频在识别结束或取消后删除，不发送云端"
                )
                Divider()
                FeatureRow(
                    icon: "keyboard.badge.ellipsis",
                    title: "快捷键与输入目标",
                    detail: "自动准备开关会记住你的选择。监听 Fn 和目标变化，不记录按键内容；只在选中洛克时响应录音"
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
