import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(
                isProminent ? .regular.tint(.accentColor) : .regular,
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    static var glassProminent: GlassButtonStyle { GlassButtonStyle(isProminent: true) }
}

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 12

    init(cornerRadius: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct GlassSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct GlassMenuRow<Content: View>: View {
    let content: Content
    var icon: String?
    var action: () -> Void

    @State private var isHovered = false

    init(icon: String? = nil, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                content
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct GlassToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    @State private var isHovered = false

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct GlassMenuSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 2) {
            content
        }
    }
}

struct GlassMenuDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
    }
}
