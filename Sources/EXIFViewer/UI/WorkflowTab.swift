import SwiftUI

struct WorkflowTab: View {
    @EnvironmentObject var model: AppModel
    var file: ImageFile
    var search: String

    private var graph: ComfyGraph? { file.comfyPrompt ?? file.comfyWorkflow }

    var body: some View {
        if let graph {
            VStack(spacing: 0) {
                summaryBar(graph)
                Divider().overlay(Theme.hairline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredNodes(graph)) { node in
                            NodeCard(node: node, graph: graph)
                        }
                        if filteredNodes(graph).isEmpty {
                            EmptyHint(icon: "magnifyingglass", title: "검색 결과 없음",
                                      subtitle: "‘\(search)’와 일치하는 노드가 없습니다")
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            EmptyHint(icon: "point.3.connected.trianglepath.dotted",
                      title: "ComfyUI 워크플로우 없음",
                      subtitle: "ComfyUI가 저장한 PNG(tEXt: prompt/workflow) 또는\nWebP/JPEG(EXIF)만 그래프를 복원할 수 있습니다.")
        }
    }

    private func summaryBar(_ graph: ComfyGraph) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Chip(text: "노드 \(graph.nodes.count)개", color: Theme.violet, icon: "circle.grid.3x3.fill")
                Chip(text: "클래스 \(graph.classCounts.count)종", color: Theme.accent)
                Text(graph.source).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button { model.exportWorkflowJSON() } label: {
                    Label("워크플로우 JSON 저장", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless).foregroundStyle(Theme.accent)
                CopyButton(text: MetaFormat.prettyJSON(graph.raw), label: "JSON 복사")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(graph.classCounts.prefix(14), id: \.0) { item in
                        Chip(text: "\(item.0) ×\(item.1)", color: .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.panel.opacity(0.5))
    }

    private func filteredNodes(_ graph: ComfyGraph) -> [ComfyNode] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return graph.nodes }
        return graph.nodes.filter { node in
            node.classType.lowercased().contains(q)
                || node.displayTitle.lowercased().contains(q)
                || node.id.lowercased() == q
                || node.inputs.contains {
                    $0.name.lowercased().contains(q)
                        || MetaFormat.scalar($0.value.literalValue ?? "").lowercased().contains(q)
                }
        }
    }
}

struct NodeCard: View {
    var node: ComfyNode
    var graph: ComfyGraph
    @State private var expanded = false

    private var accentColor: Color {
        let c = node.classType.lowercased()
        if c.contains("sampler") { return Theme.violet }
        if c.contains("cliptextencode") || c.contains("text") { return Theme.positive }
        if c.contains("loader") || c.contains("checkpoint") { return Theme.accent }
        if c.contains("save") || c.contains("preview") { return Theme.amber }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(node.id)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.displayTitle).font(.system(size: 12, weight: .semibold))
                        if node.displayTitle != node.classType {
                            Text(node.classType).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        if !expanded, !node.literalSummary.isEmpty {
                            Text(node.literalSummary)
                                .font(Theme.monoSmall).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer()
                    if !node.linkedInputs.isEmpty {
                        Chip(text: "입력 \(node.linkedInputs.count)", color: .secondary, icon: "arrow.right.circle")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().overlay(Theme.hairline)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(node.inputs.enumerated()), id: \.offset) { _, pair in
                        inputRow(pair.name, pair.value)
                    }
                    if node.inputs.isEmpty {
                        Text("입력 없음").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    HStack {
                        Spacer()
                        CopyButton(text: nodeJSON, label: "노드 JSON")
                    }
                }
                .padding(12)
            }
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline))
        .overlay(alignment: .leading) {
            Rectangle().fill(accentColor.opacity(0.8)).frame(width: 2.5)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private func inputRow(_ name: String, _ value: ComfyInput) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            switch value {
            case .literal(let v):
                let text = MetaFormat.scalar(v)
                if text.count > 160 {
                    CodeBlock(text: text, accent: accentColor, maxHeight: 140)
                } else {
                    Text(text.isEmpty ? "—" : text)
                        .font(Theme.monoSmall).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .link(let nodeID, let slot):
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left").font(.system(size: 8, weight: .bold))
                    Text("node \(nodeID)").font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    Text(graph.node(nodeID)?.displayTitle ?? "?")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Text("slot \(slot)").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private var nodeJSON: String {
        var dict: [String: Any] = ["class_type": node.classType, "id": node.id]
        var inputs: [String: Any] = [:]
        for pair in node.inputs {
            switch pair.value {
            case .literal(let v): inputs[pair.name] = MetaFormat.scalar(v)
            case .link(let n, let s): inputs[pair.name] = [n, s] as [Any]
            }
        }
        dict["inputs"] = inputs
        return MetaFormat.prettyJSON(dict)
    }
}
