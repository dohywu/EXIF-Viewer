import SwiftUI

enum Theme {
    static let accent = Color(red: 0.26, green: 0.68, blue: 0.95)
    static let positive = Color(red: 0.35, green: 0.78, blue: 0.55)
    static let negative = Color(red: 0.93, green: 0.45, blue: 0.45)
    static let amber = Color(red: 0.95, green: 0.72, blue: 0.33)
    static let violet = Color(red: 0.65, green: 0.52, blue: 0.95)

    static let panel = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let hairline = Color.primary.opacity(0.09)

    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let label = Font.system(size: 11, weight: .semibold)
    static let sectionTitle = Font.system(size: 11, weight: .bold)
}

/// Rounded container used for every block of content.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, systemImage: String? = nil,
         accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(title.uppercased())
                        .font(Theme.sectionTitle)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    accessory
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                Divider().overlay(Theme.hairline)
            }
            content.padding(14)
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct Chip: View {
    var text: String
    var color: Color = Theme.accent
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.28)))
    }
}

/// Key on the left, selectable value on the right.
struct FieldRow: View {
    var key: String
    var value: String?
    var monospaced = false
    var color: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(Theme.label)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "—")
                .font(monospaced ? Theme.mono : .system(size: 12))
                .foregroundStyle(color ?? .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct CopyButton: View {
    var text: String
    var label: String = "복사"
    @State private var done = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { done = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { done = false }
            }
        } label: {
            Label(done ? "복사됨" : label, systemImage: done ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10.5, weight: .medium))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(done ? Theme.positive : Theme.accent)
        .help("클립보드에 복사")
    }
}

/// Monospaced, scrollable, selectable text block.
struct CodeBlock: View {
    var text: String
    var accent: Color = Theme.accent
    var maxHeight: CGFloat? = nil

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "—" : text)
                .font(Theme.mono)
                .textSelection(.enabled)
                .lineSpacing(2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: maxHeight)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(accent.opacity(0.18))
        )
    }
}

struct EmptyHint: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
