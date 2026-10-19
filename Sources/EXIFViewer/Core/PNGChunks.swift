import Foundation
import Compression

/// One raw chunk read straight from the PNG stream.
struct PNGChunk {
    var type: String
    var length: Int
    var offset: Int
    /// Decoded text for tEXt / zTXt / iTXt chunks.
    var keyword: String?
    var text: String?
    var compressed = false
}

enum PNGReader {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func isPNG(_ data: Data) -> Bool {
        data.count > 8 && Array(data.prefix(8)) == signature
    }

    /// Walks every chunk in the file. ComfyUI writes its `prompt` and `workflow`
    /// JSON as tEXt chunks, A1111 writes `parameters`; some tools use zTXt/iTXt.
    static func chunks(in data: Data) -> [PNGChunk] {
        guard isPNG(data) else { return [] }
        var result: [PNGChunk] = []
        var i = 8
        let bytes = [UInt8](data)
        while i + 8 <= bytes.count {
            let length = Int(be32(bytes, i))
            let typeBytes = bytes[(i + 4)..<min(i + 8, bytes.count)]
            let type = String(bytes: typeBytes, encoding: .ascii) ?? "????"
            let dataStart = i + 8
            let dataEnd = dataStart + length
            guard length >= 0, dataEnd + 4 <= bytes.count else { break }
            var chunk = PNGChunk(type: type, length: length, offset: i)
            let payload = Data(bytes[dataStart..<dataEnd])
            switch type {
            case "tEXt":
                if let (k, v) = splitNull(payload) {
                    chunk.keyword = string(k)
                    chunk.text = string(v)
                }
            case "zTXt":
                if let (k, rest) = splitNull(payload), rest.count > 1 {
                    chunk.keyword = string(k)
                    chunk.compressed = true
                    chunk.text = inflate(rest.dropFirst()).flatMap { string($0) }
                }
            case "iTXt":
                if let parsed = parseITXt(payload) {
                    chunk.keyword = parsed.0
                    chunk.text = parsed.1
                    chunk.compressed = parsed.2
                }
            default:
                break
            }
            result.append(chunk)
            if type == "IEND" { break }
            i = dataEnd + 4
        }
        return result
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
    }

    private static func splitNull(_ data: Data) -> (Data, Data)? {
        guard let idx = data.firstIndex(of: 0) else { return nil }
        return (data[data.startIndex..<idx], data[(idx + 1)...])
    }

    private static func string(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// iTXt: keyword \0 compressionFlag compressionMethod language \0 translatedKeyword \0 text
    private static func parseITXt(_ payload: Data) -> (String, String, Bool)? {
        guard let (kw, rest) = splitNull(payload), rest.count >= 2 else { return nil }
        let flag = rest.first ?? 0
        var cursor = rest.dropFirst(2)
        guard let (_, afterLang) = splitNull(cursor) else { return nil }
        cursor = afterLang
        guard let (_, afterTranslated) = splitNull(cursor) else { return nil }
        let body = afterTranslated
        let text: String?
        if flag == 1 {
            text = inflate(body).flatMap { string($0) }
        } else {
            text = string(body)
        }
        guard let keyword = string(kw), let text else { return nil }
        return (keyword, text, flag == 1)
    }

    /// zlib stream (RFC 1950) -> raw bytes. Compression framework wants the raw
    /// deflate payload, so the 2-byte zlib header and the trailing adler32 go.
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 6 else { return nil }
        let raw = data.dropFirst(2).dropLast(4)
        var out = Data()
        var capacity = max(raw.count * 8, 64 * 1024)
        for _ in 0..<6 {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { buffer.deallocate() }
            let written = raw.withUnsafeBytes { src -> Int in
                guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(buffer, capacity, base, raw.count, nil, COMPRESSION_ZLIB)
            }
            if written > 0 && written < capacity {
                out = Data(bytes: buffer, count: written)
                return out
            }
            capacity *= 4
        }
        return out.isEmpty ? nil : out
    }
}
