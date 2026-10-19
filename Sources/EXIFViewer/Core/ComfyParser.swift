import Foundation

enum ComfyInput {
    case literal(Any)
    case link(node: String, slot: Int)

    var display: String {
        switch self {
        case .literal(let v): return MetaFormat.scalar(v)
        case .link(let node, let slot): return "→ node \(node) [\(slot)]"
        }
    }
    var literalValue: Any? {
        if case .literal(let v) = self { return v }
        return nil
    }
}

struct ComfyNode: Identifiable, Hashable {
    var id: String
    var classType: String
    var title: String?
    var order: Int
    var inputs: [(name: String, value: ComfyInput)]

    static func == (a: ComfyNode, b: ComfyNode) -> Bool { a.id == b.id && a.classType == b.classType }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(classType) }

    var displayTitle: String {
        if let t = title, !t.isEmpty, t != classType { return t }
        return classType
    }
    var literalSummary: String {
        inputs.compactMap { pair -> String? in
            guard let v = pair.value.literalValue else { return nil }
            let s = MetaFormat.scalar(v)
            return "\(pair.name): \(s.count > 90 ? String(s.prefix(90)) + "…" : s)"
        }.joined(separator: "  ·  ")
    }
    var linkedInputs: [(name: String, value: ComfyInput)] {
        inputs.filter { if case .link = $0.value { return true } else { return false } }
    }
}

struct LoraUse: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var modelStrength: String?
    var clipStrength: String?
    var nodeID: String
}

/// One sampling pass found in the graph, with everything that fed it.
struct GenerationPass: Identifiable {
    let id = UUID()
    var samplerNodeID: String
    var samplerClass: String
    var positive: String?
    var negative: String?
    var model: String?
    var vae: String?
    var loras: [LoraUse] = []
    var seed: String?
    var steps: String?
    var cfg: String?
    var samplerName: String?
    var scheduler: String?
    var denoise: String?
    var width: String?
    var height: String?
    var batchSize: String?
}

struct ComfyGraph {
    var nodes: [ComfyNode] = []
    var source: String            // which metadata key it came from
    var raw: Any                   // original JSON for the raw tab

    func node(_ id: String) -> ComfyNode? { nodes.first { $0.id == id } }

    var classCounts: [(String, Int)] {
        Dictionary(grouping: nodes, by: { $0.classType })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }
}

enum ComfyParser {
    /// API ("prompt") format: { "<id>": { class_type, inputs, _meta } }
    static func parsePrompt(_ json: Any, source: String) -> ComfyGraph? {
        guard let dict = json as? [String: Any], !dict.isEmpty else { return nil }
        var nodes: [ComfyNode] = []
        for (key, value) in dict {
            guard let nodeDict = value as? [String: Any],
                  let classType = nodeDict["class_type"] as? String else { continue }
            let meta = nodeDict["_meta"] as? [String: Any]
            var inputs: [(String, ComfyInput)] = []
            if let rawInputs = nodeDict["inputs"] as? [String: Any] {
                for name in rawInputs.keys.sorted() {
                    inputs.append((name, classify(rawInputs[name]!)))
                }
            }
            nodes.append(ComfyNode(id: key, classType: classType,
                                   title: meta?["title"] as? String,
                                   order: Int(key) ?? 0, inputs: inputs))
        }
        guard !nodes.isEmpty else { return nil }
        nodes.sort { $0.order < $1.order }
        return ComfyGraph(nodes: nodes, source: source, raw: json)
    }

    /// GUI ("workflow") format: { nodes: [...], links: [[id, from, slot, to, slot, type]] }
    static func parseWorkflow(_ json: Any, source: String) -> ComfyGraph? {
        guard let dict = json as? [String: Any],
              let rawNodes = dict["nodes"] as? [[String: Any]] else { return nil }
        var linkOrigin: [Int: (String, Int)] = [:]
        if let links = dict["links"] as? [[Any]] {
            for l in links where l.count >= 3 {
                guard let lid = intValue(l[0]) else { continue }
                let origin = MetaFormat.scalar(l[1])
                linkOrigin[lid] = (origin, intValue(l[2]) ?? 0)
            }
        }
        var nodes: [ComfyNode] = []
        for n in rawNodes {
            let id = MetaFormat.scalar(n["id"] ?? "?")
            let type = n["type"] as? String ?? "Unknown"
            var inputs: [(String, ComfyInput)] = []
            if let widgets = n["widgets_values"] as? [Any] {
                for (i, w) in widgets.enumerated() { inputs.append(("widget[\(i)]", .literal(w))) }
            } else if let widgets = n["widgets_values"] as? [String: Any] {
                for k in widgets.keys.sorted() { inputs.append((k, .literal(widgets[k]!))) }
            }
            if let ins = n["inputs"] as? [[String: Any]] {
                for inp in ins {
                    let name = inp["name"] as? String ?? "input"
                    if let lid = intValue(inp["link"] ?? NSNull()), let origin = linkOrigin[lid] {
                        inputs.append((name, .link(node: origin.0, slot: origin.1)))
                    }
                }
            }
            nodes.append(ComfyNode(id: id, classType: type, title: n["title"] as? String,
                                   order: Int(id) ?? 0, inputs: inputs))
        }
        guard !nodes.isEmpty else { return nil }
        nodes.sort { $0.order < $1.order }
        return ComfyGraph(nodes: nodes, source: source, raw: json)
    }

    private static func classify(_ value: Any) -> ComfyInput {
        if let arr = value as? [Any], arr.count == 2, let first = arr.first {
            let node = MetaFormat.scalar(first)
            if !(first is [Any]) && !(first is [String: Any]) {
                return .link(node: node, slot: intValue(arr[1]) ?? 0)
            }
        }
        return .literal(value)
    }

    private static func intValue(_ any: Any) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    // MARK: - Semantic extraction

    private static let textKeys = ["text", "text_g", "text_l", "string", "prompt",
                                   "populated_text", "wildcard_text", "value", "positive", "negative"]
    private static let modelKeys = ["ckpt_name", "unet_name", "model_name", "model_path",
                                    "model", "base_ckpt_name"]

    /// Follows links backwards until a literal string that looks like a prompt.
    static func resolveText(_ graph: ComfyGraph, from nodeID: String, depth: Int = 0, seen: Set<String> = []) -> String? {
        guard depth < 24, !seen.contains(nodeID), let node = graph.node(nodeID) else { return nil }
        var visited = seen
        visited.insert(nodeID)
        for key in textKeys {
            if let pair = node.inputs.first(where: { $0.name == key }),
               let s = pair.value.literalValue as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
        }
        // Conditioning combiners / encoders that take their text from upstream.
        for pair in node.inputs {
            if case .link(let upstream, _) = pair.value {
                if let found = resolveText(graph, from: upstream, depth: depth + 1, seen: visited) { return found }
            }
        }
        // Workflow format: unnamed widgets, first long string wins.
        if let widget = node.inputs.first(where: {
            ($0.value.literalValue as? String).map { $0.count > 2 } ?? false
        }), let s = widget.value.literalValue as? String {
            return s
        }
        return nil
    }

    /// Follows a model chain (LoRA loaders, patchers) to the checkpoint name.
    static func resolveModel(_ graph: ComfyGraph, from nodeID: String, depth: Int = 0) -> String? {
        guard depth < 24, let node = graph.node(nodeID) else { return nil }
        if !node.classType.lowercased().contains("lora") {
            for key in modelKeys {
                if let pair = node.inputs.first(where: { $0.name == key }),
                   let s = pair.value.literalValue as? String, !s.isEmpty { return s }
            }
        }
        // Walk the model chain first: LoRA loaders and patchers sit between the
        // sampler and the checkpoint, and their own file name is not the model.
        for pair in node.inputs where ["model", "unet", "base_model", "model_patch"].contains(pair.name) {
            if case .link(let upstream, _) = pair.value,
               let found = resolveModel(graph, from: upstream, depth: depth + 1) { return found }
        }
        for pair in node.inputs {
            if case .link(let upstream, _) = pair.value,
               let found = resolveModel(graph, from: upstream, depth: depth + 1) { return found }
        }
        let c = node.classType.lowercased()
        if c.contains("loader"), !c.contains("lora"), !c.contains("controlnet"), !c.contains("upscale"),
           let widget = node.inputs.first(where: { ($0.value.literalValue as? String)?.isEmpty == false }),
           let s = widget.value.literalValue as? String { return s }
        return nil
    }

    static func resolveLiteral(_ graph: ComfyGraph, node nodeID: String, key: String, depth: Int = 0) -> String? {
        guard depth < 12, let node = graph.node(nodeID) else { return nil }
        if let pair = node.inputs.first(where: { $0.name == key }) {
            switch pair.value {
            case .literal(let v):
                let s = MetaFormat.scalar(v)
                return s.isEmpty ? nil : s
            case .link(let upstream, _):
                // Primitive nodes feed widget values through links.
                if let up = graph.node(upstream) {
                    if let lit = up.inputs.first(where: { $0.name == key || $0.name == "value" })?.value.literalValue {
                        return MetaFormat.scalar(lit)
                    }
                    if let first = up.inputs.first(where: { $0.value.literalValue != nil })?.value.literalValue {
                        return MetaFormat.scalar(first)
                    }
                }
            }
        }
        return nil
    }

    static func loras(_ graph: ComfyGraph) -> [LoraUse] {
        graph.nodes.compactMap { node in
            let c = node.classType.lowercased()
            guard c.contains("lora") else { return nil }
            let name = node.inputs.first(where: { $0.name.contains("lora_name") })?.value.literalValue as? String
                ?? node.inputs.compactMap { $0.value.literalValue as? String }.first(where: { !$0.isEmpty })
            guard let name, !name.isEmpty else { return nil }
            return LoraUse(name: name,
                           modelStrength: resolveLiteral(graph, node: node.id, key: "strength_model"),
                           clipStrength: resolveLiteral(graph, node: node.id, key: "strength_clip"),
                           nodeID: node.id)
        }
    }

    /// Every sampling pass in the graph, newest-style samplers included.
    static func passes(_ graph: ComfyGraph) -> [GenerationPass] {
        let samplers = graph.nodes.filter { node in
            let c = node.classType.lowercased()
            let looksSampler = c.contains("sampler") || c.contains("ksampler")
            let hasCond = node.inputs.contains { ["positive", "negative", "guider", "cond"].contains($0.name) }
            return looksSampler || (hasCond && c.contains("sample"))
        }
        let allLoras = loras(graph)
        return samplers.map { sampler in
            var pass = GenerationPass(samplerNodeID: sampler.id, samplerClass: sampler.displayTitle)
            func upstream(_ name: String) -> String? {
                if case .link(let n, _)? = sampler.inputs.first(where: { $0.name == name })?.value { return n }
                return nil
            }
            if let p = upstream("positive") { pass.positive = resolveText(graph, from: p) }
            if let n = upstream("negative") { pass.negative = resolveText(graph, from: n) }
            if pass.positive == nil, let g = upstream("guider") { pass.positive = resolveText(graph, from: g) }
            if let m = upstream("model") { pass.model = resolveModel(graph, from: m) }
            if pass.model == nil { pass.model = graph.nodes.compactMap { n -> String? in
                n.classType.lowercased().contains("checkpointloader")
                    ? n.inputs.first(where: { $0.name.contains("ckpt_name") })?.value.literalValue as? String : nil
            }.first }
            pass.vae = graph.nodes.compactMap { n -> String? in
                n.classType.lowercased().contains("vaeloader")
                    ? n.inputs.first(where: { $0.name.contains("vae_name") })?.value.literalValue as? String : nil
            }.first
            pass.seed = resolveLiteral(graph, node: sampler.id, key: "seed")
                ?? resolveLiteral(graph, node: sampler.id, key: "noise_seed")
            if pass.seed == nil, let noise = upstream("noise") {
                pass.seed = resolveLiteral(graph, node: noise, key: "noise_seed")
                    ?? resolveLiteral(graph, node: noise, key: "seed")
            }
            pass.steps = resolveLiteral(graph, node: sampler.id, key: "steps")
            pass.cfg = resolveLiteral(graph, node: sampler.id, key: "cfg")
            pass.samplerName = resolveLiteral(graph, node: sampler.id, key: "sampler_name")
            pass.scheduler = resolveLiteral(graph, node: sampler.id, key: "scheduler")
            pass.denoise = resolveLiteral(graph, node: sampler.id, key: "denoise")
            if pass.steps == nil || pass.scheduler == nil {
                // Custom-sampler graphs keep steps/scheduler on a *SchedulerNode.
                for n in graph.nodes where n.classType.lowercased().contains("scheduler") || n.classType.lowercased().contains("sigmas") {
                    pass.steps = pass.steps ?? resolveLiteral(graph, node: n.id, key: "steps")
                    pass.scheduler = pass.scheduler ?? resolveLiteral(graph, node: n.id, key: "scheduler")
                    pass.denoise = pass.denoise ?? resolveLiteral(graph, node: n.id, key: "denoise")
                }
                for n in graph.nodes where n.classType.lowercased().contains("samplerselect") {
                    pass.samplerName = pass.samplerName ?? resolveLiteral(graph, node: n.id, key: "sampler_name")
                }
            }
            if let latent = upstream("latent_image") ?? upstream("latent") {
                pass.width = resolveLiteral(graph, node: latent, key: "width")
                pass.height = resolveLiteral(graph, node: latent, key: "height")
                pass.batchSize = resolveLiteral(graph, node: latent, key: "batch_size")
            }
            if pass.width == nil {
                for n in graph.nodes where n.inputs.contains(where: { $0.name == "width" }) {
                    pass.width = pass.width ?? resolveLiteral(graph, node: n.id, key: "width")
                    pass.height = pass.height ?? resolveLiteral(graph, node: n.id, key: "height")
                }
            }
            pass.loras = allLoras
            return pass
        }
    }
}
