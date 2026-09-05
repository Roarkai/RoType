import AppKit
import RoTypeCore
import SwiftUI
@preconcurrency import Translation

private enum SettingsSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case candidates = "双语候选"
    case translation = "本地翻译"
    case privacy = "隐私与诊断"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .candidates: "character.bubble"
        case .translation: "translate"
        case .privacy: "lock.shield"
        }
    }
}

struct RoTypeSettingsRootView: View {
    @ObservedObject var settings: RoTypeSettings
    @State private var onboardingStep: Int

    init(settings: RoTypeSettings) {
        self.settings = settings
        _onboardingStep = State(initialValue: settings.initialOnboardingStep)
    }

    var body: some View {
        Group {
            if settings.onboardingCompleted {
                SettingsHomeView(settings: settings)
            } else {
                OnboardingView(settings: settings, step: $onboardingStep)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .task { await settings.refreshTranslationAvailability() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await settings.refreshTranslationAvailability() }
        }
        .onChange(of: settings.onboardingCompleted) { _, completed in
            if !completed { onboardingStep = settings.initialOnboardingStep }
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var settings: RoTypeSettings
    @Binding var step: Int
    @StateObject private var inputSource = InputSourceManager()
    @State private var completionError = ""
    private let titles = ["输入法", "本地翻译"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(titles.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.18))
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Group {
                if step == 0 {
                    InputSourceSetupPane(manager: inputSource, settings: settings)
                } else {
                    TranslationSettingsPane(settings: settings)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            if !completionError.isEmpty {
                Text(completionError)
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
            HStack {
                Button("稍后设置") { NSApp.keyWindow?.close() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                if step == titles.count - 1 && !settings.translationReady {
                    Button("先用静态热词") {
                        settings.translationDeferred = true
                        completeOnboarding()
                    }
                    .disabled(!settings.keyboardStepComplete(
                        isReady: inputSource.isReady, currentVerification: inputSource.selectionVerified
                    ))
                }
                if step > 0 {
                    Button("上一步") { step -= 1 }
                }
                Button(step == titles.count - 1 ? "完成" : "继续") {
                    if step == titles.count - 1 {
                        completeOnboarding()
                    } else {
                        completionError = ""
                        step += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            }
            .padding(20)
        }
        .onAppear { if !inputSource.isReady { step = 0 } }
    }

    private var canAdvance: Bool {
        switch step {
        case 0:
            settings.keyboardStepComplete(
                isReady: inputSource.isReady, currentVerification: inputSource.selectionVerified
            )
        default:
            settings.canFinishSetup(
                isReady: inputSource.isReady, currentVerification: inputSource.selectionVerified
            )
        }
    }

    private func completeOnboarding() {
        inputSource.refreshCurrentState()
        guard settings.keyboardStepComplete(
            isReady: inputSource.isReady, currentVerification: inputSource.selectionVerified
        ) else {
            completionError = "请先启用并切换到洛克输入法，确认它可以正常输入。"
            step = 0
            return
        }
        if !settings.canFinishSetup(isReady: inputSource.isReady, currentVerification: inputSource.selectionVerified) {
            completionError = "请准备语言包，或选择先用静态热词；以后可在设置中继续。"
            step = 1
            return
        }
        completionError = ""
        settings.onboardingCompleted = true
    }
}

private struct InputSourceSetupPane: View {
    @ObservedObject var manager: InputSourceManager
    @ObservedObject var settings: RoTypeSettings
    var compact = false
    @State private var verificationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if compact {
                Text("键盘输入法").font(.headline)
            } else {
                PaneTitle("启用洛克输入法", detail: "启用后即可输入中文；下一步可准备本地翻译。")
            }
            SettingsCard {
                HStack(spacing: 14) {
                    Image(
                        systemName: keyboardConfigured
                            ? "checkmark.circle.fill"
                            : "keyboard"
                    )
                        .font(.title2)
                        .foregroundStyle(keyboardConfigured ? Color.green : Color.accentColor)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(keyboardConfigured ? "输入法已配置" : "需要启用并验证")
                            .font(.headline)
                        Text(keyboardConfigured && !manager.selectionVerified
                             ? "已完成输入配置；可在下方重新验证当前会话。" : manager.status)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(manager.isWorking ? "正在准备..." :
                        (settings.keyboardVerified && manager.isReady ? "切换到洛克" : "打开系统设置添加")) {
                        if settings.keyboardVerified && manager.isReady {
                            manager.enableAndSelect()
                        } else {
                            manager.openKeyboardSettings()
                        }
                    }
                    .disabled(manager.isWorking)
                }
            }
            if !keyboardConfigured {
                Text("系统设置 → 键盘 → 文本输入「编辑」→ ＋ → 简体中文 → 洛克输入法。添加后，请从顶部菜单选择洛克，再回这里试打。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !compact {
                Text("全拼 / 小鹤双拼可在输入法菜单切换。候选每页 5 项；Tab 直接提交独立译文。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextField("在这里试打 nihao，空格选择中文", text: $verificationText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("重新检查") { manager.refresh() }
                Button("打开键盘设置") { manager.openKeyboardSettings() }
            }
        }
        .onAppear { manager.refresh() }
        .onChange(of: manager.selectionVerified) { _, verified in
            if verified { settings.recordKeyboardVerification() }
        }
    }

    private var keyboardConfigured: Bool {
        settings.keyboardStepComplete(isReady: manager.isReady, currentVerification: manager.selectionVerified)
    }
}

private struct SettingsHomeView: View {
    @ObservedObject var settings: RoTypeSettings
    @State private var selection: SettingsSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            ScrollView {
                Group {
                    switch selection ?? .overview {
                    case .overview: OverviewPane(settings: settings)
                    case .candidates: CandidateSettingsPane()
                    case .translation: TranslationSettingsPane(settings: settings)
                    case .privacy: PrivacyPane()
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(selection?.rawValue ?? "洛克输入法设置")
        }
    }
}

private struct OverviewPane: View {
    @ObservedObject var settings: RoTypeSettings
    @StateObject private var inputSource = InputSourceManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneTitle(
                "洛克输入法",
                detail: translationSummary
            )
            SettingsCard {
                FeatureRow(icon: "number", title: "五项候选", detail: "每页最多 5 项；译文独立显示，Tab 直接上屏")
                Divider()
                FeatureRow(icon: "translate", title: "本地翻译", detail: "使用 Apple 系统语言能力生成动态候选")
            }
            InputSourceSetupPane(manager: inputSource, settings: settings, compact: true)
            Button("重新运行配置向导") { settings.restartOnboarding() }
        }
    }
}

private extension OverviewPane {
    var translationSummary: String {
        switch settings.translationStatus {
        case .checking: "正在检查本地翻译能力，不会重新下载已有语言包。"
        case .ready: "动态中英翻译语言包已准备。输入源状态见下方。"
        case .needsPreparation: "静态热词可用；动态翻译可稍后准备，不影响普通中文输入。"
        case .staticOnly: "当前系统支持静态热词；动态翻译需 macOS 26。"
        }
    }
}

private struct CandidateSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle("双语候选", detail: "保持翻译候选容易选择，同时不让原始拼音挤占常用中文候选。")
            SettingsCard {
                FeatureRow(icon: "5.circle", title: "紧凑候选", detail: "每页最多 5 项，支持键盘与滚轮翻页")
                Divider()
                FeatureRow(icon: "arrow.right.to.line", title: "Tab 直接选用译文", detail: "翻译跟随当前高亮项；点击或按 Tab 上屏，无需再按回车")
                Divider()
                FeatureRow(icon: "character", title: "简体中文", detail: "仅输出简体候选，不启用繁体转换")
            }
        }
    }
}

private struct TranslationSettingsPane: View {
    @ObservedObject var settings: RoTypeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle("本地中英翻译", detail: "动态候选使用 Apple 简体中文与英文语言能力。")
            if #available(macOS 26.0, *) {
                TranslationPackView(settings: settings)
            } else {
                SettingsCard {
                    FeatureRow(
                        icon: "exclamationmark.triangle",
                        title: "当前系统仅支持静态双语热词",
                        detail: "任意短语的 Apple 动态翻译需要 macOS 26"
                    )
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private struct TranslationPackView: View {
    @ObservedObject var settings: RoTypeSettings
    @State private var configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: "zh-Hans"),
        target: Locale.Language(identifier: "en")
    )
    @State private var shouldPrepare = false
    @State private var status = "尚未检查简体中文与英文语言包。"

    var body: some View {
        SettingsCard {
            FeatureRow(icon: "arrow.left.arrow.right", title: "简体中文到英文", detail: status)
            HStack {
                Spacer()
                Button(shouldPrepare ? "正在准备..." : "检查并准备语言包") {
                    shouldPrepare = true
                    status = "正在检查语言包..."
                    configuration.invalidate()
                }
                .disabled(shouldPrepare)
            }
        }
        .translationTask(configuration) { session in
            guard shouldPrepare else { return }
            do {
                try await session.prepareTranslation()
                let availability = LanguageAvailability()
                let chinese = Locale.Language(identifier: "zh-Hans")
                let english = Locale.Language(identifier: "en")
                for _ in 0..<30 {
                    try Task.checkCancellation()
                    let zhEN = await availability.status(from: chinese, to: english)
                    let enZH = await availability.status(from: english, to: chinese)
                    if zhEN == .installed && enZH == .installed {
                        status = "语言包已准备，动态双语候选可用。"
                        settings.setTranslationReady(true)
                        shouldPrepare = false
                        return
                    }
                    if zhEN == .unsupported || enZH == .unsupported {
                        status = "系统暂不支持该语言对，可先用静态热词。"
                        shouldPrepare = false
                        return
                    }
                    status = "正在等待语言包就绪。"
                    try await Task.sleep(for: .seconds(2))
                }
                status = "语言包尚未就绪，可稍后重新检查；不影响中文输入。"
                shouldPrepare = false
            } catch is CancellationError {
                shouldPrepare = false
                status = "准备已暂停，可重新检查。"
                return
            } catch {
                status = error.localizedDescription
                shouldPrepare = false
            }
        }
        .task { await refreshAvailability() }
    }

    private func refreshAvailability() async {
        await settings.refreshTranslationAvailability()
        if Task.isCancelled { return }
        status = settings.translationReady
            ? "语言包已准备，动态双语候选可用。"
            : "可先用静态热词，稍后再准备动态翻译语言包。"
    }
}
