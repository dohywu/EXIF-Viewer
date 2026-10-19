import SwiftUI

struct MetadataTreeTab: View {
    var file: ImageFile
    var search: String

    private var roots: [MetaNode] {
        let all = file.propertyTree + file.xmpTree + chunkNodes
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.compactMap { $0.filtered(q) }
    }

    /// PNG chunk layout as its own group — byte offsets and sizes included.
    private var chunkNodes: [MetaNode] {
        guard !file.chunks.isEmpty else { return [] }
        let children = file.chunks.enumerated().map { idx, chunk -> MetaNode in
            var kids: [MetaNode] = [
                MetaNode(key: "type", value: chunk.type, children: nil, path: "PNG chunks[\(idx)].type"),
                MetaNode(key: "length", value: "\(chunk.length) bytes", children: nil, path: "PNG chunks[\(idx)].length"),
                MetaNode(key: "offset", value: "0x" + String(chunk.offset, radix: 16), children: nil, path: "PNG chunks[\(idx)].offset")
            ]
            if let k = chunk.keyword {
                kids.append(MetaNode(key: "keyword", value: k, children: nil, path: "PNG chunks[\(idx)].keyword"))
            }
            if let t = chunk.text {
                kids.append(MetaNode(key: "text", value: t, children: nil, path: "PNG chunks[\(idx)].text"))
            }
            if chunk.compressed {
                kids.append(MetaNode(key: "compression", value: "deflate (zlib)", children: nil, path: "PNG chunks[\(idx)].compression"))
            }
            let label = chunk.keyword.map { "\(chunk.type) · \($0)" } ?? chunk.type
            return MetaNode(key: label, value: "\(chunk.length) bytes", children: kids, path: "PNG chunks[\(idx)]")
        }
        return [MetaNode(key: "PNG chunks", value: "\(children.count) chunks",
                         children: children, path: "PNG chunks")]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Chip(text: "항목 \(file.allFlattened.count)개", color: Theme.accent, icon: "list.bullet")
                if !file.chunks.isEmpty {
                    Chip(text: "PNG 청크 \(file.chunks.count)개", color: Theme.violet)
                }
                Spacer()
                CopyButton(text: file.allFlattened.map { "\($0.0) = \($0.1)" }.joined(separator: "\n"),
                           label: "전체 복사")
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Theme.panel.opacity(0.5))
            Divider().overlay(Theme.hairline)

            if roots.isEmpty {
                EmptyHint(icon: "list.bullet.indent", title: "표시할 메타데이터 없음",
                          subtitle: search.isEmpty ? "이미지에 메타데이터가 없습니다" : "‘\(search)’ 검색 결과 없음")
            } else {
                List {
                    ForEach(roots) { root in
                        TreeRow(node: root, depth: 0, expandDefault: !search.isEmpty || root.children?.count ?? 0 < 12)
                    }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 22)
            }
        }
    }
}

struct TreeRow: View {
    var node: MetaNode
    var depth: Int
    var expandDefault: Bool
    @State private var expanded: Bool?

    private var isExpanded: Bool { expanded ?? (expandDefault && depth < 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let children = node.children {
                Button { expanded = !isExpanded } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).frame(width: 9)
                        Image(systemName: "folder.fill").font(.system(size: 9)).foregroundStyle(Theme.accent.opacity(0.8))
                        Text(node.key).font(.system(size: 11.5, weight: .semibold))
                        Text(node.value ?? "").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(children) { child in
                        TreeRow(node: child, depth: depth + 1, expandDefault: expandDefault)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(node.key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: max(120, 190 - CGFloat(depth) * 14), alignment: .leading)
                    Text(node.value ?? "—")
                        .font(Theme.monoSmall)
                        .textSelection(.enabled)
                        .lineLimit(node.value?.count ?? 0 > 400 ? 6 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CopyButton(text: node.value ?? "", label: "")
                        .labelStyle(.iconOnly)
                        .opacity(0.65)
                }
                .padding(.leading, CGFloat(depth) * 14 + 15)
                .padding(.vertical, 1)
            }
        }
    }
}
