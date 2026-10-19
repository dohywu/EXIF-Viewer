import SwiftUI

struct DetailView: View {
    @EnvironmentObject var model: AppModel
    var file: ImageFile

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            tabBar
            Divider().overlay(Theme.hairline)
            content
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Chip(text: file.typeDescription, color: .secondary, icon: "doc")
                    Chip(text: file.dimensions, color: Theme.accent, icon: "aspectratio")
                    if let mp = file.megapixels { Chip(text: mp, color: .secondary) }
                    Chip(text: MetaFormat.bytes(file.fileSize), color: .secondary)
                    if file.isComfy {
                        Chip(text: "ComfyUI 워크플로우 발견", color: Theme.violet, icon: "checkmark.seal.fill")
                    } else if file.a1111 != nil {
                        Chip(text: "A1111 파라미터", color: Theme.amber, icon: "sparkles")
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.panel.opacity(0.6))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { tab in
                let badge = badgeCount(tab)
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { model.tab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 10, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 11.5, weight: .medium))
                        if let badge {
                            Text("\(badge)")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.primary.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(model.tab == tab ? Theme.accent.opacity(0.16) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(model.tab == tab ? Theme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if model.tab == .exif || model.tab == .workflow {
                SearchField(text: $model.search)
                    .frame(width: 220)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.panel.opacity(0.35))
    }

    private func badgeCount(_ tab: DetailTab) -> Int? {
        switch tab {
        case .workflow:
            let graph = file.comfyPrompt ?? file.comfyWorkflow
            return graph?.nodes.count
        case .prompt:
            return file.passes.isEmpty ? (file.a1111 == nil ? nil : 1) : file.passes.count
        case .raw:
            return file.payloads.isEmpty ? nil : file.payloads.count
        default:
            return nil
        }
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .overview: OverviewTab(file: file)
        case .prompt: PromptTab(file: file)
        case .workflow: WorkflowTab(file: file, search: model.search)
        case .exif: MetadataTreeTab(file: file, search: model.search)
        case .raw: RawTab(file: file)
        }
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
            TextField("검색", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
