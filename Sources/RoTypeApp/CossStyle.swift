import AppKit
import SwiftUI

// Native interpretation of COSS UI, not a webview or a React dependency.
// Source: cosscom/coss @ 705cb737c341d701ad981548e88d50da239694bd,
// packages/ui/src/styles/globals.css and apps/ui/registry/default/ui/{button,card,switch}.tsx.
enum CossStyle {
    static let background = neutral(light: 1, dark: 0.08)
    static let surface = neutral(light: 1, dark: 0.10)
    static let sidebar = neutral(light: 0.98, dark: 0.07)
    static let text = neutral(light: 0.15, dark: 0.96)
    static let muted = neutral(light: 0.40, dark: 0.67)
    static let border = neutral(light: 0.91, dark: 0.20)
    static let accent = neutral(light: 0.96, dark: 0.16)

    private static func neutral(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: darkMode ? dark : light, alpha: 1)
        })
    }
}

struct SettingsSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 13))
            .foregroundStyle(CossStyle.text)
            .background(CossStyle.background)
            .tint(CossStyle.text)
            .buttonStyle(CossButtonStyle())
    }
}

struct CossButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        CossButtonSurface(configuration: configuration, primary: primary)
    }
}

private struct CossButtonSurface: View {
    let configuration: ButtonStyle.Configuration
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(primary ? CossStyle.background : CossStyle.text)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? CossStyle.muted : CossStyle.border, lineWidth: focused ? 2 : 1))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .onHover { hovered = $0 }
    }

    private var background: Color {
        primary ? CossStyle.text : (hovered || configuration.isPressed ? CossStyle.accent : CossStyle.surface)
    }
}

struct CossTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text).textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 12).frame(height: 36)
            .background(CossStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? CossStyle.muted : CossStyle.border, lineWidth: focused ? 2 : 1))
    }
}

struct SettingsGroupTitle: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(CossStyle.text)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(CossStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium))
            .foregroundStyle(CossStyle.muted)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(CossStyle.accent, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(CossStyle.border, lineWidth: 0.5))
    }
}
