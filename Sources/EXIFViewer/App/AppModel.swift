import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var files: [ImageFile] = []
    @Published var selectionID: ImageFile.ID?
    @Published var isLoading = false
    @Published var isDropTargeted = false
    @Published var tab: DetailTab = .overview
    @Published var search = ""

    var selected: ImageFile? {
        files.first { $0.id == selectionID } ?? files.first
    }

    static let supportedTypes: [UTType] = [.image, .png, .jpeg, .tiff, .webP, .heic, .gif, .bmp]

    func open(urls: [URL]) {
        let expanded = Self.expand(urls)
        guard !expanded.isEmpty else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let loaded = expanded.map { MetadataLoader.load(url: $0) }
            await MainActor.run {
                // Re-dropping a file replaces its entry instead of duplicating it.
                for file in loaded {
                    if let idx = self.files.firstIndex(where: { $0.url == file.url }) {
                        self.files[idx] = file
                    } else {
                        self.files.append(file)
                    }
                }
                self.selectionID = loaded.first.flatMap { new in
                    self.files.first { $0.url == new.url }?.id
                }
                self.isLoading = false
            }
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { open(urls: panel.urls) }
    }

    func remove(_ id: ImageFile.ID) {
        files.removeAll { $0.id == id }
        if selectionID == id { selectionID = files.first?.id }
    }

    func clear() {
        files.removeAll()
        selectionID = nil
    }

    func revealInFinder() {
        guard let url = selected?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Accepts dropped providers of file URLs; folders are scanned one level deep.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.open(urls: urls)
        }
        return true
    }

    private static func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles])) ?? []
                out += contents.filter { isImage($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else if isImage(url) {
                out.append(url)
            }
        }
        return out
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .image)
    }

    /// Full dump of everything known about the selected file, for the Export action.
    func exportReport() {
        guard let file = selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "-metadata.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report(for: file).write(to: url, atomically: true, encoding: .utf8)
    }

    func report(for file: ImageFile) -> String {
        var out = ["FILE: \(file.url.path)",
                   "SIZE: \(MetaFormat.bytes(file.fileSize))   \(file.dimensions)",
                   "GENERATOR: \(file.generator)", ""]
        for pass in file.passes {
            out.append("── SAMPLER \(pass.samplerNodeID) (\(pass.samplerClass)) ──")
            out.append("Positive: \(pass.positive ?? "—")")
            out.append("Negative: \(pass.negative ?? "—")")
            out.append("Model: \(pass.model ?? "—")  Seed: \(pass.seed ?? "—")  Steps: \(pass.steps ?? "—")  CFG: \(pass.cfg ?? "—")")
            out.append("Sampler: \(pass.samplerName ?? "—")  Scheduler: \(pass.scheduler ?? "—")  Denoise: \(pass.denoise ?? "—")")
            out.append("")
        }
        out.append("── METADATA ──")
        out += file.allFlattened.map { "\($0.0) = \($0.1)" }
        out.append("")
        out.append("── EMBEDDED TEXT ──")
        for p in file.payloads {
            out.append("[\(p.source) · \(p.key)]")
            out.append(p.text)
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// Writes the ComfyUI graph back out so it can be loaded into ComfyUI again.
    func exportWorkflowJSON() {
        guard let file = selected,
              let graph = file.comfyWorkflow ?? file.comfyPrompt else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "-workflow.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? MetaFormat.prettyJSON(graph.raw).write(to: url, atomically: true, encoding: .utf8)
    }
}
