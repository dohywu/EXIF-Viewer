import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectionID) {
                Section {
                    ForEach(model.files) { file in
                        FileRow(file: file)
                            .tag(file.id)
                            .contextMenu {
                                Button("Finder에서 보기") {
                                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                }
                                Button("경로 복사") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(file.url.path, forType: .string)
                                }
                                Divider()
                                Button("목록에서 제거", role: .destructive) { model.remove(file.id) }
                            }
                    }
                } header: {
                    Text("불러온 이미지 \(model.files.count)")
                        .font(Theme.sectionTitle).tracking(0.6)
                }
            }
            .listStyle(.sidebar)

            Divider().overlay(Theme.hairline)
            HStack(spacing: 8) {
                Button { model.openPanel() } label: {
                    Label("추가", systemImage: "plus").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                Spacer()
                Button { model.clear() } label: {
                    Label("비우기", systemImage: "trash").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(model.files.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}

struct FileRow: View {
    var file: ImageFile

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.07))
                if let thumb = file.thumbnail {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(file.dimensions)
                    Text("·")
                    Text(MetaFormat.bytes(file.fileSize))
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                if file.isComfy {
                    Chip(text: "ComfyUI", color: Theme.violet, icon: "point.3.filled.connected.trianglepath.dotted")
                } else if file.a1111 != nil {
                    Chip(text: "A1111", color: Theme.amber, icon: "sparkles")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
