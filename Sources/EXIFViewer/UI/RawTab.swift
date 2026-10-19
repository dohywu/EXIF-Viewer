import SwiftUI

struct RawTab: View {
    var file: ImageFile
    @State private var selected: TextPayload.ID?

    private var entries: [TextPayload] {
        var list = file.payloads
        // Surface the reconstructed graphs even when they came from one payload.
        if let graph = file.comfyPrompt {
            list.append(TextPayload(source: "해석된 그래프", key: "prompt (API format)",
                                    text: MetaFormat.prettyJSON(graph.raw)))
        }
        if let graph = file.comfyWorkflow {
            list.append(TextPayload(source: "해석된 그래프", key: "workflow (GUI format)",
                                    text: MetaFormat.prettyJSON(graph.raw)))
        }
        for (key, json) in file.otherJSON {
            list.append(TextPayload(source: "기타 JSON", key: key, text: MetaFormat.prettyJSON(json)))
        }
        return list
    }

    private var current: TextPayload? {
        entries.first { $0.id == selected } ?? entries.first
    }

    var body: some View {
        if entries.isEmpty {
            EmptyHint(icon: "curlybraces", title: "원본 텍스트 데이터 없음",
                      subtitle: "PNG tEXt/zTXt/iTXt 청크나 EXIF 텍스트 태그가 없습니다")
        } else {
            HSplitView {
                List(selection: $selected) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.key).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 4) {
                                Chip(text: entry.source, color: .secondary)
                                if entry.looksJSON { Chip(text: "JSON", color: Theme.violet) }
                                if entry.compressed { Chip(text: "deflate", color: Theme.amber) }
                            }
                            Text(MetaFormat.bytes(Int64(entry.byteCount)))
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .tag(entry.id)
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 190, idealWidth: 230, maxWidth: 300)

                VStack(spacing: 0) {
                    if let current {
                        HStack(spacing: 8) {
                            Text(current.key).font(.system(size: 12, weight: .semibold))
                            Chip(text: current.source, color: Theme.accent)
                            Text("\(current.text.count)자 · \(MetaFormat.bytes(Int64(current.byteCount)))")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                            Spacer()
                            CopyButton(text: current.text)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.panel.opacity(0.5))
                        Divider().overlay(Theme.hairline)
                        ScrollView([.vertical, .horizontal]) {
                            Text(displayText(current))
                                .font(Theme.mono)
                                .textSelection(.enabled)
                                .lineSpacing(2.5)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minWidth: 380)
            }
        }
    }

    /// JSON payloads read far better pretty-printed.
    private func displayText(_ payload: TextPayload) -> String {
        if payload.looksJSON, let json = MetadataLoader.jsonObject(payload.text) {
            return MetaFormat.prettyJSON(json)
        }
        return payload.text
    }
}
