import Foundation

/// A single node in the generic metadata tree. Leaves carry a formatted value,
/// containers carry children (dictionaries and arrays from the image metadata).
struct MetaNode: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String?
    var children: [MetaNode]?
    /// Full dotted path from the root, used for search and for copying.
    var path: String = ""

    var isLeaf: Bool { children == nil }

    /// Flattened `path = value` lines for the whole subtree.
    func flattened() -> [(String, String)] {
        if let children {
            return children.flatMap { $0.flattened() }
        }
        return [(path.isEmpty ? key : path, value ?? "")]
    }

    /// Returns a copy of the subtree keeping only nodes matching `query`
    /// (matching a container keeps the whole container).
    func filtered(_ query: String) -> MetaNode? {
        let q = query.lowercased()
        if q.isEmpty { return self }
        let selfMatch = key.lowercased().contains(q) || (value?.lowercased().contains(q) ?? false)
        if let children {
            let kept = children.compactMap { $0.filtered(query) }
            if selfMatch || !kept.isEmpty {
                var copy = self
                copy.children = kept.isEmpty ? children : kept
                return copy
            }
            return nil
        }
        return selfMatch ? self : nil
    }
}

enum MetaFormat {
    /// Converts an arbitrary property-list / JSON value coming from ImageIO or
    /// JSONSerialization into a MetaNode tree.
    static func node(key: String, value: Any, path: String) -> MetaNode {
        let childPath = path.isEmpty ? key : path
        switch value {
        case let dict as [String: Any]:
            let children = dict.keys.sorted().map {
                node(key: $0, value: dict[$0]!, path: "\(childPath).\($0)")
            }
            return MetaNode(key: key, value: "\(dict.count) item\(dict.count == 1 ? "" : "s")",
                            children: children, path: childPath)
        case let dict as [AnyHashable: Any]:
            let remapped = Dictionary(uniqueKeysWithValues: dict.map { ("\($0.key)", $0.value) })
            return node(key: key, value: remapped, path: path)
        case let array as [Any]:
            // Short scalar arrays read better on one line.
            if array.count <= 8, array.allSatisfy({ !($0 is [Any]) && !($0 is [AnyHashable: Any]) }) {
                return MetaNode(key: key, value: array.map { scalar($0) }.joined(separator: ", "),
                                children: nil, path: childPath)
            }
            let children = array.enumerated().map {
                node(key: "[\($0.offset)]", value: $0.element, path: "\(childPath)[\($0.offset)]")
            }
            return MetaNode(key: key, value: "\(array.count) items", children: children, path: childPath)
        default:
            return MetaNode(key: key, value: scalar(value), children: nil, path: childPath)
        }
    }

    static func scalar(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            if n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e15 {
                return String(n.int64Value)
            }
            return String(format: "%g", n.doubleValue)
        case let d as Date: return ISO8601DateFormatter().string(from: d)
        case let d as Data: return "<\(d.count) bytes> " + d.prefix(24).map { String(format: "%02x", $0) }.joined()
        case let u as URL: return u.path
        default: return String(describing: value)
        }
    }

    static func bytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: count)
    }

    /// Pretty-prints any JSON-compatible value with stable key order.
    static func prettyJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value) || value is [Any] else {
            return scalar(value)
        }
        let opts: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: opts),
              let text = String(data: data, encoding: .utf8) else { return scalar(value) }
        return text
    }
}
