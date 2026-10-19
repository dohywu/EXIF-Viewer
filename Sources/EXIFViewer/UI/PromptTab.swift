import SwiftUI

struct PromptTab: View {
    var file: ImageFile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if file.passes.isEmpty && file.a1111 == nil {
                    EmptyHint(icon: "text.alignleft",
                              title: "프롬프트 정보 없음",
                              subtitle: "이 이미지에는 ComfyUI/A1111 생성 메타데이터가 없습니다.\n‘EXIF · 전체’ 또는 ‘원본 데이터’ 탭을 확인하세요.")
                } else {
                    ForEach(Array(file.passes.enumerated()), id: \.element.id) { index, pass in
                        passCard(index: index, pass: pass)
                    }
                    if let a = file.a1111 { a1111Section(a) }
                }
            }
            .padding(16)
        }
    }

    private func passCard(index: Int, pass: GenerationPass) -> some View {
        Card("샘플링 패스 #\(index + 1) · \(pass.samplerClass)",
             systemImage: "wand.and.rays",
             accessory: AnyView(HStack(spacing: 6) {
                 Chip(text: "node \(pass.samplerNodeID)", color: Theme.violet)
                 if let seed = pass.seed { Chip(text: "seed \(seed)", color: Theme.amber) }
             })) {
            VStack(alignment: .leading, spacing: 12) {
                block("Positive prompt", pass.positive, Theme.positive, "plus.circle.fill")
                block("Negative prompt", pass.negative, Theme.negative, "minus.circle.fill")

                VStack(alignment: .leading, spacing: 1) {
                    FieldRow(key: "Checkpoint", value: pass.model, monospaced: true, color: Theme.accent)
                    FieldRow(key: "VAE", value: pass.vae, monospaced: true)
                    FieldRow(key: "Steps / CFG", value: joined([pass.steps, pass.cfg], " / "), monospaced: true)
                    FieldRow(key: "Sampler", value: pass.samplerName, monospaced: true)
                    FieldRow(key: "Scheduler", value: pass.scheduler, monospaced: true)
                    FieldRow(key: "Denoise", value: pass.denoise, monospaced: true)
                    FieldRow(key: "Latent", value: latentText(pass), monospaced: true)
                }

                if !pass.loras.isEmpty {
                    Divider().overlay(Theme.hairline)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("LORA \(pass.loras.count)개").font(Theme.label).foregroundStyle(.secondary)
                        ForEach(pass.loras) { lora in
                            HStack(spacing: 6) {
                                Text("node \(lora.nodeID)").font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                Text(lora.name).font(Theme.monoSmall).textSelection(.enabled)
                                Spacer()
                                if let m = lora.modelStrength { Chip(text: "model \(m)", color: Theme.violet) }
                                if let c = lora.clipStrength { Chip(text: "clip \(c)", color: .secondary) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func block(_ title: String, _ text: String?, _ color: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color)
                Text(title).font(Theme.label).foregroundStyle(color)
                if let text { Text("\(text.count)자").font(.system(size: 10)).foregroundStyle(.tertiary) }
                Spacer()
                if let text, !text.isEmpty { CopyButton(text: text) }
            }
            CodeBlock(text: text ?? "—", accent: color, maxHeight: 240)
        }
    }

    private func a1111Section(_ a: A1111Params) -> some View {
        Card("Stable Diffusion 파라미터", systemImage: "sparkles",
             accessory: AnyView(CopyButton(text: a.positive, label: "Positive"))) {
            VStack(alignment: .leading, spacing: 12) {
                block("Positive prompt", a.positive, Theme.positive, "plus.circle.fill")
                block("Negative prompt", a.negative, Theme.negative, "minus.circle.fill")
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(a.fields, id: \.0) { FieldRow(key: $0.0, value: $0.1, monospaced: true) }
                }
            }
        }
    }

    private func joined(_ values: [String?], _ sep: String) -> String? {
        let parts = values.compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: sep)
    }

    private func latentText(_ pass: GenerationPass) -> String? {
        guard let w = pass.width, let h = pass.height else { return nil }
        if let b = pass.batchSize { return "\(w) × \(h)  ·  batch \(b)" }
        return "\(w) × \(h)"
    }
}
