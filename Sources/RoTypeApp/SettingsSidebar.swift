import SwiftUI

struct SettingsSidebar: View {
    let items: [(title: String, icon: String)]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("R").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CossStyle.background)
                    .frame(width: 28, height: 28)
                    .background(CossStyle.text, in: RoundedRectangle(cornerRadius: 7))
                Text("洛克输入法").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 30)
            Text("设置").font(.system(size: 11, weight: .medium)).foregroundStyle(CossStyle.muted)
                .padding(.horizontal, 20).padding(.bottom, 10)
            VStack(spacing: 4) {
                ForEach(items, id: \.title) { item in
                    Button { selection = item.title } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon).font(.system(size: 14)).frame(width: 18)
                            Text(item.title)
                                .font(.system(size: 12, weight: selection == item.title ? .medium : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == item.title ? CossStyle.text : CossStyle.muted)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(selection == item.title ? CossStyle.accent : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SidebarButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityAddTraits(selection == item.title ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 30)
            Link(destination: URL(string: "https://type.roarkist.com/")!) {
                Image(systemName: "globe")
                    .font(.system(size: 16))
                    .foregroundStyle(CossStyle.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(SidebarButtonStyle())
            .focusEffectDisabled()
            .accessibilityLabel("洛克输入法官网")
            .help("type.roarkist.com")
            .padding(16)
        }
        .frame(width: 184)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(CossStyle.sidebar)
    }
}

// Keep keyboard navigation, with a neutral focus background rather than the system blue ring.
private struct SidebarButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(focused ? CossStyle.border : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
