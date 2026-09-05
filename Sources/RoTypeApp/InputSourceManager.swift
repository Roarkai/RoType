import AppKit
import Carbon
import Combine
import Foundation
import RoTypeCore

private enum InputSourceControllerBridge {
    static let request = Notification.Name("im.roarkai.inputmethod.Luoke.verification-request")
    static let status = Notification.Name("im.roarkai.inputmethod.Luoke.controller-status")
    static let sourceIdentifier = "im.roarkai.inputmethod.Luoke.Hans"
    static let requestIDKey = "requestID"
}

@MainActor
final class InputSourceManager: ObservableObject {
    static let identifier = InputSourceControllerBridge.sourceIdentifier
    static let bundleURL = URL(fileURLWithPath: "/Library/Input Methods/洛克输入法.app", isDirectory: true)
    static let setupRequiredMarker = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RoType/input-source-setup-required")

    @Published private(set) var isInstalled = false
    @Published private(set) var isReady = false
    @Published private(set) var isSelected = false
    @Published private(set) var selectionVerified = false
    @Published private(set) var isWorking = false
    @Published private(set) var status = "正在检查输入法状态…"
    private var controllerHandledInput = false
    private var verificationRequestID = ""
    private var baselineControllerInputGeneration: Int64?
    private let verificationClient = ControllerInputVerificationClient()

    init() {
        let distributed = DistributedNotificationCenter.default()
        let sourceNotifications = [
            kTISNotifySelectedKeyboardInputSourceChanged,
            kTISNotifyEnabledKeyboardInputSourcesChanged
        ].compactMap { $0 as String? }.map { Notification.Name($0) }
        for name in sourceNotifications {
            distributed.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        distributed.addObserver(
            forName: InputSourceControllerBridge.status,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let sourceIdentifier = notification.object as? String
            let requestID = notification.userInfo?[InputSourceControllerBridge.requestIDKey] as? String
            Task { @MainActor in
                self?.receiveControllerStatus(
                    sourceIdentifier: sourceIdentifier,
                    requestID: requestID
                )
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        refreshInputSourceState()
        requestFreshControllerEvidence()
    }

    func refreshCurrentState() {
        refreshInputSourceState()
    }

    private func refreshInputSourceState() {
        guard let source = inputSource(includeAllInstalled: true) else {
            isInstalled = false
            isReady = false
            isSelected = false
            selectionVerified = false
            status = "尚未在系统中注册洛克输入法。"
            return
        }
        isInstalled = true
        let enabled = boolProperty(source, key: kTISPropertyInputSourceIsEnabled)
        let selectable = boolProperty(source, key: kTISPropertyInputSourceIsSelectCapable)
        isReady = enabled && selectable
        let currentIdentifier = currentInputSourceIdentifier()
        isSelected = InputSourceSelectionVerifier.isVerified(
            targetIdentifier: Self.identifier,
            currentIdentifier: currentIdentifier,
            controllerHandledInput: true
        )
        selectionVerified = InputSourceSelectionVerifier.isVerified(
            targetIdentifier: Self.identifier,
            currentIdentifier: currentIdentifier,
            controllerHandledInput: controllerHandledInput
        )
        if selectionVerified {
            try? FileManager.default.removeItem(at: Self.setupRequiredMarker)
            status = "洛克输入法已处理真实键盘输入。"
        } else if isSelected {
            status = "系统状态已切到洛克输入法，请在下方输入框键入字母完成验证。"
        } else if isReady {
            status = "系统已识别洛克输入法。请从顶部输入法菜单选中后，在下方输入框键入任意按键。"
        } else {
            status = "洛克输入法已安装，但还未启用。"
        }
    }

    private func requestFreshControllerEvidence() {
        controllerHandledInput = false
        baselineControllerInputGeneration = nil
        verificationRequestID = UUID().uuidString
        let requestID = verificationRequestID
        refreshInputSourceState()
        verificationClient.currentGeneration { [weak self] result in
            guard let self, self.verificationRequestID == requestID else { return }
            switch result {
            case let .success(generation):
                self.baselineControllerInputGeneration = generation
                DistributedNotificationCenter.default().postNotificationName(
                    InputSourceControllerBridge.request,
                    object: Self.identifier,
                    userInfo: [InputSourceControllerBridge.requestIDKey: requestID],
                    deliverImmediately: true
                )
            case .failure:
                self.status = "无法连接输入法验证服务，请重新检查。"
            }
        }
    }

    private func receiveControllerStatus(
        sourceIdentifier: String?,
        requestID: String?
    ) {
        guard sourceIdentifier == Self.identifier,
              requestID == verificationRequestID,
              baselineControllerInputGeneration != nil else { return }
        checkControllerEvidence(requestID: verificationRequestID, remainingAttempts: 4)
    }

    private func checkControllerEvidence(requestID: String, remainingAttempts: Int) {
        verificationClient.currentGeneration { [weak self] result in
            guard let self,
                  self.verificationRequestID == requestID,
                  let baseline = self.baselineControllerInputGeneration else { return }
            if case let .success(generation) = result,
               InputSourceSelectionVerifier.hasFreshControllerInput(
                   baseline: baseline,
                   current: generation
               ) {
                self.controllerHandledInput = true
                self.refreshInputSourceState()
            } else if remainingAttempts > 1 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(50))
                    self?.checkControllerEvidence(
                        requestID: requestID,
                        remainingAttempts: remainingAttempts - 1
                    )
                }
            }
        }
    }

    func enableAndSelect() {
        guard !isWorking else { return }
        isWorking = true
        status = "正在注册并启用洛克输入法…"

        Task { @MainActor in
            if inputSource(includeAllInstalled: true) == nil {
                let registration = TISRegisterInputSource(Self.bundleURL as CFURL)
                guard registration == noErr else {
                    finishWithError("注册失败（错误码 \(registration)）。请确认已完成安装。")
                    return
                }
            }

            guard let source = inputSource(includeAllInstalled: true) else {
                finishWithError("系统尚未识别洛克输入法，请打开键盘设置后重试。")
                return
            }
            // Always call the public enable operation. macOS can expose a
            // synthetic enabled property before the mode is present in the
            // user's real input menu.
            let enableResult = TISEnableInputSource(source)
            guard enableResult == noErr else {
                finishWithError("启用失败（错误码 \(enableResult)）。")
                return
            }

            let selectionResult = TISSelectInputSource(source)
            guard selectionResult == noErr else {
                finishWithError("切换失败（错误码 \(selectionResult)）。请从系统输入菜单手动选择洛克输入法。")
                openKeyboardSettings()
                return
            }

            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(150))
                refreshInputSourceState()
                if isReady && isSelected {
                    isWorking = false
                    return
                }
            }
            isWorking = false
            refresh()
            if !isReady {
                status = "系统没有确认启用状态，请打开键盘设置后重试。"
            }
        }
    }

    func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func finishWithError(_ message: String) {
        isWorking = false
        isReady = false
        isSelected = false
        selectionVerified = false
        status = message
    }

    private func inputSource(includeAllInstalled: Bool) -> TISInputSource? {
        guard let sources = TISCreateInputSourceList(nil, includeAllInstalled).takeRetainedValue()
            as? [TISInputSource] else { return nil }
        return sources.first { source in
            stringProperty(source, key: kTISPropertyInputSourceID) == Self.identifier
        }
    }

    private func currentInputSourceIdentifier() -> String? {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return stringProperty(current, key: kTISPropertyInputSourceID)
    }

    private func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        let value = TISGetInputSourceProperty(source, key)
        return unsafeBitCast(value, to: CFString?.self) as String?
    }

    private func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
        let value = TISGetInputSourceProperty(source, key)
        guard let boolean = unsafeBitCast(value, to: CFBoolean?.self) else { return false }
        return CFBooleanGetValue(boolean)
    }
}
