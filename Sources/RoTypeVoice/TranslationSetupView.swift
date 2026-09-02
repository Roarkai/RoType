import SwiftUI
@preconcurrency import Translation

@available(macOS 15.0, *)
struct TranslationSetupView: View {
    @State private var configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: "zh-Hans"),
        target: Locale.Language(identifier: "en")
    )
    @State private var shouldPrepare = false
    @State private var status = "准备后，翻译内容默认在设备上处理。"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RoType 中英动态候选")
                .font(.title2.weight(.semibold))
            Text("下载 Apple 中英翻译语言包后，任意完整短语都可以生成反向语言候选。")
                .fixedSize(horizontal: false, vertical: true)
            Text(status)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(shouldPrepare ? "语言包下载中…" : "准备中英语言包") {
                    shouldPrepare = true
                    status = "正在检查语言包…"
                    configuration.invalidate()
                }
                .disabled(shouldPrepare)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440, height: 220)
        .translationTask(configuration) { session in
            guard shouldPrepare else { return }
            do {
                try await session.prepareTranslation()
                status = "语言包下载中，可在系统设置的“翻译语言”中查看进度…"

                let availability = LanguageAvailability()
                let chinese = Locale.Language(identifier: "zh-Hans")
                let english = Locale.Language(identifier: "en")
                while !Task.isCancelled {
                    let chineseToEnglish = await availability.status(from: chinese, to: english)
                    let englishToChinese = await availability.status(from: english, to: chinese)
                    if chineseToEnglish == .installed && englishToChinese == .installed {
                        status = "中英翻译语言包已准备，可以使用动态候选。"
                        shouldPrepare = false
                        return
                    }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch is CancellationError {
                return
            } catch {
                status = error.localizedDescription
                shouldPrepare = false
            }
        }
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationSetupWindowController: NSWindowController {
    convenience init() {
        let controller = NSHostingController(rootView: TranslationSetupView())
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 440, height: 220))
        window.title = "RoType 翻译设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}
