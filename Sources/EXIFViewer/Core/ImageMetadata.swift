import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct TextPayload: Identifiable, Hashable {
    let id = UUID()
    var source: String       // "PNG tEXt", "EXIF UserComment", "XMP", …
    var key: String
    var text: String
    var compressed = false
    var byteCount: Int { text.utf8.count }
    var looksJSON: Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("{") || t.hasPrefix("[")
    }
}

struct A1111Params {
    var positive: String
    var negative: String?
    var fields: [(String, String)]
}

struct ImageFile: Identifiable {
    let id = UUID()
    var url: URL
    var fileSize: Int64 = 0
    var created: Date?
    var modified: Date?
    var typeDescription: String = "—"
    var pixelWidth: Int?
    var pixelHeight: Int?
    var bitDepth: Int?
    var colorModel: String?
    var colorProfile: String?
    var dpi: Double?
    var orientation: String?
    var thumbnail: NSImage?

    var propertyTree: [MetaNode] = []     // everything ImageIO knows
    var xmpTree: [MetaNode] = []
    var chunks: [PNGChunk] = []
    var payloads: [TextPayload] = []

    var comfyPrompt: ComfyGraph?
    var comfyWorkflow: ComfyGraph?
    var passes: [GenerationPass] = []
    var a1111: A1111Params?
    var otherJSON: [(String, Any)] = []
    var errorMessage: String?

    var name: String { url.lastPathComponent }
    var isComfy: Bool { comfyPrompt != nil || comfyWorkflow != nil }
    var dimensions: String {
        guard let w = pixelWidth, let h = pixelHeight else { return "—" }
        return "\(w) × \(h)"
    }
    var megapixels: String? {
        guard let w = pixelWidth, let h = pixelHeight else { return nil }
        return String(format: "%.1f MP", Double(w * h) / 1_000_000)
    }
    var generator: String {
        if isComfy { return "ComfyUI" }
        if a1111 != nil { return "Stable Diffusion (A1111/Forge)" }
        if payloads.contains(where: { $0.key.lowercased().contains("sd-metadata") || $0.key.lowercased() == "invokeai_metadata" }) {
            return "InvokeAI"
        }
        if let desc = propertyValue("{TIFF}.Software") { return desc }
        if payloads.contains(where: { $0.text.lowercased().contains("midjourney") }) { return "Midjourney" }
        return "—"
    }
    /// Lookup inside the flattened ImageIO tree.
    func propertyValue(_ path: String) -> String? {
        for root in propertyTree {
            for (p, v) in root.flattened() where p == path || p.hasSuffix("." + path) {
                return v
            }
        }
        return nil
    }
    var allFlattened: [(String, String)] {
        propertyTree.flatMap { $0.flattened() } + xmpTree.flatMap { $0.flattened() }
    }
}

enum MetadataLoader {

    static func load(url: URL) -> ImageFile {
        var file = ImageFile(url: url)
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path) {
            file.fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            file.created = attrs[.creationDate] as? Date
            file.modified = attrs[.modificationDate] as? Date
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            file.typeDescription = type.localizedDescription ?? type.identifier
        }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            file.errorMessage = "파일을 읽을 수 없습니다."
            return file
        }

        // ---- ImageIO: every property dictionary the system can decode.
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                file.pixelWidth = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue
                file.pixelHeight = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue
                file.bitDepth = (props[kCGImagePropertyDepth as String] as? NSNumber)?.intValue
                file.colorModel = props[kCGImagePropertyColorModel as String] as? String
                file.colorProfile = props[kCGImagePropertyProfileName as String] as? String
                file.dpi = (props[kCGImagePropertyDPIWidth as String] as? NSNumber)?.doubleValue
                if let o = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue {
                    file.orientation = orientationName(o)
                }
                var roots: [MetaNode] = []
                for key in props.keys.sorted() {
                    roots.append(MetaFormat.node(key: prettyGroup(key), value: props[key]!, path: prettyGroup(key)))
                }
                file.propertyTree = roots
                file.payloads += exifPayloads(props)
            }
            if let container = CGImageSourceCopyProperties(source, nil) as? [String: Any], !container.isEmpty {
                for key in container.keys.sorted() where !(container[key] is NSNull) {
                    file.propertyTree.append(MetaFormat.node(key: "Container." + prettyGroup(key),
                                                             value: container[key]!,
                                                             path: "Container." + prettyGroup(key)))
                }
            }
            file.xmpTree = xmpNodes(source: source)
            file.thumbnail = thumbnail(source: source)
        }

        // ---- Raw PNG chunk walk: where ComfyUI and A1111 actually write.
        if PNGReader.isPNG(data) {
            file.chunks = PNGReader.chunks(in: data)
            for chunk in file.chunks {
                guard let keyword = chunk.keyword, let text = chunk.text else { continue }
                let kind = chunk.compressed ? "PNG \(chunk.type) (deflate)" : "PNG \(chunk.type)"
                file.payloads.append(TextPayload(source: kind, key: keyword, text: text, compressed: chunk.compressed))
            }
        }

        // ImageIO and the raw chunk walk can report the same text twice.
        var seen = Set<String>()
        file.payloads = file.payloads.filter { seen.insert("\($0.key.lowercased())|\($0.text)").inserted }

        // ---- Interpret the payloads.
        interpret(&file)
        file.passes = (file.comfyPrompt ?? file.comfyWorkflow).map { ComfyParser.passes($0) } ?? []
        return file
    }

    // MARK: - Payload interpretation

    private static func interpret(_ file: inout ImageFile) {
        for payload in file.payloads {
            var text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var key = payload.key
            // WebP/JPEG writers prefix the JSON, e.g. "Prompt:{…}" in EXIF Make.
            for prefix in ["Prompt:", "prompt:", "Workflow:", "workflow:"] where text.hasPrefix(prefix) {
                key = String(prefix.dropLast()).lowercased()
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let lowerKey = key.lowercased()

            if let json = jsonObject(text) {
                if lowerKey == "workflow" || (json as? [String: Any])?["nodes"] is [[String: Any]] {
                    if file.comfyWorkflow == nil,
                       let graph = ComfyParser.parseWorkflow(json, source: "\(payload.source) · \(key)") {
                        file.comfyWorkflow = graph
                        continue
                    }
                }
                if file.comfyPrompt == nil,
                   let graph = ComfyParser.parsePrompt(json, source: "\(payload.source) · \(key)") {
                    file.comfyPrompt = graph
                    continue
                }
                if file.comfyWorkflow == nil,
                   let graph = ComfyParser.parseWorkflow(json, source: "\(payload.source) · \(key)") {
                    file.comfyWorkflow = graph
                    continue
                }
                file.otherJSON.append((key, json))
                continue
            }

            if lowerKey == "parameters" || text.contains("Negative prompt:")
                || (text.contains("Steps:") && text.contains("Sampler:")) {
                file.a1111 = parseA1111(text)
            }
        }
    }

    static func jsonObject(_ text: String) -> Any? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") || t.hasPrefix("["), let data = t.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// A1111 / Forge "parameters" block.
    static func parseA1111(_ text: String) -> A1111Params {
        var positive = text
        var negative: String?
        var fields: [(String, String)] = []

        if let negRange = text.range(of: "Negative prompt:") {
            positive = String(text[text.startIndex..<negRange.lowerBound])
            let rest = String(text[negRange.upperBound...])
            // The settings line is the last line containing "Steps:" or "Sampler:".
            let lines = rest.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if let idx = lines.lastIndex(where: { $0.contains("Steps:") || $0.contains("Sampler:") || $0.contains("CFG scale:") }) {
                negative = lines[0..<idx].joined(separator: "\n")
                fields = parseSettings(lines[idx...].joined(separator: " "))
            } else {
                negative = rest
            }
        } else {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if let idx = lines.lastIndex(where: { $0.contains("Steps:") || $0.contains("Sampler:") }) {
                positive = lines[0..<idx].joined(separator: "\n")
                fields = parseSettings(lines[idx...].joined(separator: " "))
            }
        }
        return A1111Params(positive: positive.trimmingCharacters(in: .whitespacesAndNewlines),
                           negative: negative?.trimmingCharacters(in: .whitespacesAndNewlines),
                           fields: fields)
    }

    private static func parseSettings(_ line: String) -> [(String, String)] {
        line.split(separator: ",").compactMap { part in
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard let colon = piece.firstIndex(of: ":") else { return nil }
            let k = String(piece[piece.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let v = String(piece[piece.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return k.isEmpty || v.isEmpty ? nil : (k, v)
        }
    }

    // MARK: - EXIF / XMP helpers

    /// Pulls the EXIF/TIFF string fields that generators abuse as metadata slots.
    private static func exifPayloads(_ props: [String: Any]) -> [TextPayload] {
        var out: [TextPayload] = []
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let png = props[kCGImagePropertyPNGDictionary as String] as? [String: Any] ?? [:]
        let candidates: [(String, [String: Any], [String])] = [
            ("EXIF", exif, [kCGImagePropertyExifUserComment as String,
                            kCGImagePropertyExifImageUniqueID as String,
                            "MakerNote"]),
            ("TIFF", tiff, [kCGImagePropertyTIFFImageDescription as String,
                            kCGImagePropertyTIFFMake as String,
                            kCGImagePropertyTIFFModel as String,
                            kCGImagePropertyTIFFSoftware as String,
                            kCGImagePropertyTIFFArtist as String,
                            kCGImagePropertyTIFFCopyright as String]),
            ("PNG", png, ["Description", "Comment", "Software", "Title", "Author",
                          "parameters", "prompt", "workflow"])
        ]
        for (group, dict, keys) in candidates {
            for key in keys {
                guard let value = dict[key] else { continue }
                let text: String?
                if let s = value as? String { text = s }
                else if let d = value as? Data { text = String(data: d, encoding: .utf8) }
                else { text = nil }
                guard let text, text.count > 1 else { continue }
                out.append(TextPayload(source: "\(group) tag", key: key, text: text))
            }
        }
        return out
    }

    private static func xmpNodes(source: CGImageSource) -> [MetaNode] {
        guard let meta = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tags = CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag], !tags.isEmpty else { return [] }
        var nodes: [MetaNode] = []
        for tag in tags {
            nodes.append(contentsOf: xmpTagNodes(tag, parentPath: "XMP"))
        }
        return nodes.isEmpty ? [] : [MetaNode(key: "XMP", value: "\(nodes.count) tags", children: nodes, path: "XMP")]
    }

    private static func xmpTagNodes(_ tag: CGImageMetadataTag, parentPath: String) -> [MetaNode] {
        let prefix = (CGImageMetadataTagCopyPrefix(tag) as String?) ?? ""
        let name = (CGImageMetadataTagCopyName(tag) as String?) ?? "tag"
        let label = prefix.isEmpty ? name : "\(prefix):\(name)"
        let path = "\(parentPath).\(label)"
        let value = CGImageMetadataTagCopyValue(tag)
        if let nested = value as? [CGImageMetadataTag] {
            let children = nested.flatMap { xmpTagNodes($0, parentPath: path) }
            return [MetaNode(key: label, value: "\(children.count) items", children: children, path: path)]
        }
        return [MetaNode(key: label, value: MetaFormat.scalar(value as Any), children: nil, path: path)]
    }

    private static func thumbnail(source: CGImageSource) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func prettyGroup(_ key: String) -> String {
        key.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
    }

    private static func orientationName(_ v: Int) -> String {
        let names = ["", "Normal (1)", "Mirrored horizontal (2)", "Rotated 180° (3)",
                     "Mirrored vertical (4)", "Mirrored + 90° CW (5)", "Rotated 90° CW (6)",
                     "Mirrored + 90° CCW (7)", "Rotated 90° CCW (8)"]
        return v >= 0 && v < names.count ? names[v] : "\(v)"
    }
}
