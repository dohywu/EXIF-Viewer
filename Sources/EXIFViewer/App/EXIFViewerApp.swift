import SwiftUI

@main
struct EXIFViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Metadata Inspector", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear { AppDelegate.model = model }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("이미지 열기…") { model.openPanel() }
                    .keyboardShortcut("o")
                Divider()
                Button("메타데이터 리포트 내보내기…") { model.exportReport() }
                    .keyboardShortcut("e")
                    .disabled(model.selected == nil)
                Button("워크플로우 JSON 저장…") { model.exportWorkflowJSON() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.selected?.comfyWorkflow == nil && model.selected?.comfyPrompt == nil)
                Divider()
                Button("Finder에서 보기") { model.revealInFinder() }
                    .keyboardShortcut("r")
                    .disabled(model.selected == nil)
                Button("목록 비우기") { model.clear() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }
    }
}
