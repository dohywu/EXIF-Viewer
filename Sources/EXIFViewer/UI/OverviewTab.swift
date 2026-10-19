import SwiftUI

struct OverviewTab: View {
    var file: ImageFile

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                preview
                    .frame(minWidth: 280, idealWidth: 420, maxWidth: 520)
                VStack(alignment: .leading, spacing: 14) {
                    if let pass = file.passes.first { generationCard(pass) }
                    else if let a = file.a1111 { a1111Card(a) }
                    fileCard
                    imageCard
                    if let camera = cameraRows, !camera.isEmpty { cameraCard(camera) }
                    if let gps = gpsRows, !gps.isEmpty { gpsCard(gps) }
                    payloadCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    private var preview: some View {
        Card("미리보기", systemImage: "photo") {
            VStack(spacing: 10) {
                if let thumb = file.thumbnail {
                    Image(nsImage: thumb)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                } else {
                    EmptyHint(icon: "photo", title: "미리보기 없음", subtitle: "이미지를 디코딩할 수 없습니다")
                        .frame(height: 220)
                }
                HStack(spacing: 6) {
                    Chip(text: file.generator,
                         color: file.isComfy ? Theme.violet : (file.a1111 != nil ? Theme.amber : .secondary),
                         icon: "wand.and.stars")
                    if let depth = file.bitDepth { Chip(text: "\(depth)-bit", color: .secondary) }
                    if let model = file.colorModel { Chip(text: model, color: .secondary) }
                    Spacer()
                }
            }
        }
    }

    private var fileCard: some View {
        Card("파일", systemImage: "doc.text",
             accessory: AnyView(CopyButton(text: file.url.path, label: "경로"))) {
            VStack(alignment: .leading, spacing: 1) {
                FieldRow(key: "이름", value: file.name)
                FieldRow(key: "경로", value: file.url.deletingLastPathComponent().path, monospaced: true)
                FieldRow(key: "종류", value: file.typeDescription)
                FieldRow(key: "용량", value: "\(MetaFormat.bytes(file.fileSize))  (\(file.fileSize.formatted()) bytes)")
                FieldRow(key: "생성일", value: file.created.map { dateString($0) })
                FieldRow(key: "수정일", value: file.modified.map { dateString($0) })
            }
        }
    }

    private var imageCard: some View {
        Card("이미지", systemImage: "aspectratio") {
            VStack(alignment: .leading, spacing: 1) {
                FieldRow(key: "해상도", value: file.dimensions)
                FieldRow(key: "픽셀 수", value: file.megapixels)
                FieldRow(key: "색 공간", value: file.colorModel)
                FieldRow(key: "프로파일", value: file.colorProfile)
                FieldRow(key: "비트 심도", value: file.bitDepth.map { "\($0) bit" })
                FieldRow(key: "DPI", value: file.dpi.map { String(format: "%.0f", $0) })
                FieldRow(key: "방향", value: file.orientation)
            }
        }
    }

    private func generationCard(_ pass: GenerationPass) -> some View {
        Card("생성 정보 · ComfyUI", systemImage: "wand.and.stars",
             accessory: AnyView(Chip(text: "노드 \(pass.samplerNodeID) · \(pass.samplerClass)", color: Theme.violet))) {
            VStack(alignment: .leading, spacing: 10) {
                statGrid(pass)
                if let positive = pass.positive, !positive.isEmpty {
                    promptBlock("Positive", positive, Theme.positive)
                }
                if let negative = pass.negative, !negative.isEmpty {
                    promptBlock("Negative", negative, Theme.negative)
                }
                if !pass.loras.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LoRA").font(Theme.label).foregroundStyle(.secondary)
                        ForEach(pass.loras) { lora in
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3").font(.system(size: 9))
                                    .foregroundStyle(Theme.violet)
                                Text(lora.name).font(Theme.monoSmall).textSelection(.enabled)
                                if let m = lora.modelStrength { Chip(text: "model \(m)", color: .secondary) }
                                if let c = lora.clipStrength { Chip(text: "clip \(c)", color: .secondary) }
                                Spacer()
                            }
                        }
                    }
                }
                if file.passes.count > 1 {
                    Text("샘플러 \(file.passes.count)개 — ‘프롬프트’ 탭에서 전부 확인")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func statGrid(_ pass: GenerationPass) -> some View {
        let stats: [(String, String?, Color)] = [
            ("Model", pass.model, Theme.accent),
            ("Seed", pass.seed, Theme.amber),
            ("Steps", pass.steps, .primary),
            ("CFG", pass.cfg, .primary),
            ("Sampler", pass.samplerName, .primary),
            ("Scheduler", pass.scheduler, .primary),
            ("Denoise", pass.denoise, .primary),
            ("Size", (pass.width != nil && pass.height != nil) ? "\(pass.width!)×\(pass.height!)" : nil, .primary),
            ("VAE", pass.vae, .secondary)
        ].filter { $0.1 != nil }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(stats, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(.tertiary)
                    Text(item.1 ?? "—")
                        .font(Theme.monoSmall)
                        .foregroundStyle(item.2)
                        .lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func a1111Card(_ a: A1111Params) -> some View {
        Card("생성 정보 · Stable Diffusion", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(a.fields, id: \.0) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.0.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6)
                                .foregroundStyle(.tertiary)
                            Text(field.1).font(Theme.monoSmall).lineLimit(2).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                promptBlock("Positive", a.positive, Theme.positive)
                if let n = a.negative, !n.isEmpty { promptBlock("Negative", n, Theme.negative) }
            }
        }
    }

    private func promptBlock(_ title: String, _ text: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.label).foregroundStyle(color)
                Spacer()
                CopyButton(text: text)
            }
            CodeBlock(text: text, accent: color, maxHeight: 150)
        }
    }

    private var cameraRows: [(String, String)]? {
        let wanted = ["TIFF.Make", "TIFF.Model", "Exif.LensModel", "Exif.FNumber",
                      "Exif.ExposureTime", "Exif.ISOSpeedRatings", "Exif.FocalLength",
                      "Exif.DateTimeOriginal", "Exif.ExposureBiasValue", "Exif.Flash"]
        let rows = wanted.compactMap { key -> (String, String)? in
            guard let v = file.propertyValue(key) else { return nil }
            return (key.split(separator: ".").last.map(String.init) ?? key, v)
        }
        return rows.isEmpty ? nil : rows
    }

    private func cameraCard(_ rows: [(String, String)]) -> some View {
        Card("카메라 · 촬영", systemImage: "camera") {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(rows, id: \.0) { FieldRow(key: $0.0, value: $0.1) }
            }
        }
    }

    private var gpsRows: [(String, String)]? {
        let rows = file.allFlattened.filter { $0.0.hasPrefix("GPS.") }
            .map { (String($0.0.dropFirst(4)), $0.1) }
        return rows.isEmpty ? nil : rows
    }

    private func gpsCard(_ rows: [(String, String)]) -> some View {
        Card("위치 (GPS)", systemImage: "mappin.and.ellipse",
             accessory: AnyView(CopyButton(text: rows.map { "\($0.0): \($0.1)" }.joined(separator: "\n")))) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(rows.prefix(10), id: \.0) { FieldRow(key: $0.0, value: $0.1, monospaced: true) }
            }
        }
    }

    private var payloadCard: some View {
        Card("내장 텍스트 블록", systemImage: "doc.plaintext",
             accessory: AnyView(Chip(text: "\(file.payloads.count)개", color: .secondary))) {
            if file.payloads.isEmpty {
                Text("내장된 텍스트 메타데이터 없음").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(file.payloads) { p in
                        HStack(spacing: 6) {
                            Chip(text: p.source, color: p.compressed ? Theme.amber : .secondary)
                            Text(p.key).font(Theme.monoSmall).foregroundStyle(Theme.accent)
                            Text(MetaFormat.bytes(Int64(p.byteCount)))
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                            if p.looksJSON { Chip(text: "JSON", color: Theme.violet) }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
