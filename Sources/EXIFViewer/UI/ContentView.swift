import SwiftUI
import UniformTypeIdentifiers

enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "개요"
    case prompt = "프롬프트"
    case workflow = "워크플로우"
    case exif = "EXIF · 전체"
    case raw = "원본 데이터"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .prompt: return "text.alignleft"
        case .workflow: return "point.3.connected.trianglepath.dotted"
        case .exif: return "list.bullet.indent"
        case .raw: return "curlybraces"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            Group {
                if let file = model.selected {
                    DetailView(file: file)
                } else {
                    DropLanding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
        .overlay(alignment: .top) {
            if model.isDropTargeted { DropOverlay() }
        }
        .overlay(alignment: .bottom) {
            if model.isLoading { LoadingBar() }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTargeted) { providers in
            model.handleDrop(providers)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.openPanel() } label: { Image(systemName: "plus") }
                    .help("이미지 열기 (⌘O)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let file = model.selected {
                    Button { model.revealInFinder() } label: { Image(systemName: "folder") }
                        .help("Finder에서 보기")
                    Button { model.exportWorkflowJSON() } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("워크플로우 JSON 저장")
                    .disabled(!file.isComfy)
                    Button { model.exportReport() } label: { Image(systemName: "doc.text") }
                        .help("메타데이터 리포트 내보내기")
                }
            }
        }
    }
}

struct LoadingBar: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("메타데이터 읽는 중…").font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .padding(16)
    }
}

struct DropOverlay: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill").foregroundStyle(Theme.accent)
            Text("여기에 놓으면 분석합니다").font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.top, 18)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct DropLanding: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(model.isDropTargeted ? Theme.accent : Color.secondary.opacity(0.35))
                    .frame(width: 340, height: 200)
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 38, weight: .thin))
                        .foregroundStyle(Theme.accent)
                    Text("이미지를 드래그하세요")
                        .font(.system(size: 15, weight: .semibold))
                    Text("PNG · JPEG · WebP · TIFF · HEIC · 폴더")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("파일 선택…") { model.openPanel() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            VStack(spacing: 5) {
                Text("ComfyUI · A1111 · InvokeAI 생성 정보 자동 해석")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text("EXIF · IPTC · XMP · GPS · PNG tEXt/zTXt/iTXt 청크 전부 표시")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(model.isDropTargeted ? 1.02 : 1)
        .animation(.spring(response: 0.3), value: model.isDropTargeted)
    }
}
