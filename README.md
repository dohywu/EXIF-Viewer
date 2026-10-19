<p align="center">
  <img src="docs/thumbnail.webp" alt="Exif-Viewer" width="100%">
</p>

<h1 align="center">Metadata Inspector</h1>

<p align="center">
  이미지를 드래그하면 그 안에 들어 있는 모든 메타데이터를 보여주는 macOS 앱.<br>
  특히 <b>ComfyUI</b>로 생성한 이미지의 프롬프트와 워크플로우를 그대로 복원합니다.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/SwiftUI-native-0A84FF">
  <img src="https://img.shields.io/badge/dependencies-0-3FB950">
</p>

<p align="center">
  <img src="docs/screenshot-overview.png" alt="앱 화면" width="100%">
</p>

## 무엇을 읽나

| 소스 | 내용 |
| --- | --- |
| ImageIO | EXIF, TIFF, IPTC, GPS, JFIF, PNG, HEIC/WebP 컨테이너 속성, 컬러 프로파일 |
| XMP | 중첩 구조를 포함한 전체 태그 트리 |
| PNG 청크 | 모든 청크를 직접 파싱: `tEXt`, `zTXt`(zlib 해제), `iTXt` + 타입·크기·오프셋 |
| ComfyUI | `prompt`(API 그래프), `workflow`(GUI 그래프) JSON — PNG 텍스트 청크 또는 EXIF 태그에서 |
| A1111 / Forge | `parameters` 블록 → positive, negative, steps, sampler, CFG, seed, size, model hash … |
| InvokeAI · Midjourney | 내장 JSON / 텍스트 페이로드를 그대로 표시 |

## ComfyUI 해석

JSON을 그냥 덤프하지 않고 그래프를 복원해서 따라갑니다.

- **프롬프트** — 샘플러의 `positive` / `negative` 링크를 거꾸로 따라가, 실제로 샘플러에 들어간 텍스트를 찾습니다. 중간에 conditioning 노드가 몇 개 끼어 있어도 추적합니다.
- **체크포인트** — LoRA 로더와 model patcher를 통과해 끝까지 올라갑니다. LoRA 파일명을 체크포인트로 착각하지 않습니다.
- **샘플링 값** — seed, steps, CFG, sampler, scheduler, denoise, latent 크기. 커스텀 샘플러 그래프(`*SchedulerNode`, `SamplerSelect`, `RandomNoise`)에 흩어져 있어도 모읍니다.
- **LoRA** — 전부 나열하고 model/clip strength까지 표시. VAE 로더도 함께.
- 샘플링 패스가 여러 개면 패스마다 카드가 따로 생깁니다.
- **노드 브라우저** — 검색·펼치기 가능. 각 입력은 리터럴 값이거나 어느 노드에서 연결됐는지 보여줍니다. 워크플로우 JSON을 내보내 ComfyUI에 다시 불러올 수 있습니다.

## 탭 구성

1. **개요** — 미리보기, 생성 정보 요약, 파일·이미지 정보, 카메라/GPS(있을 때)
2. **프롬프트** — 샘플링 패스별 카드, 프롬프트마다 복사 버튼
3. **워크플로우** — 노드 브라우저, 검색, JSON 내보내기
4. **EXIF · 전체** — 모든 속성·XMP 태그·PNG 청크의 검색 가능한 트리
5. **원본 데이터** — 원본 텍스트 페이로드(JSON은 보기 좋게 정렬)

## 빌드

```bash
./build.sh            # dist/Metadata Inspector.app
./build.sh --install  # /Applications 에 바로 설치
```

의존성 없음. Swift 6 / SwiftUI / ImageIO / Compression 만 사용합니다. 결과물은 ad-hoc 서명된 네이티브 앱(macOS 14+).

## 단축키

| 키 | 동작 |
| --- | --- |
| ⌘O | 이미지 또는 폴더 열기 |
| ⌘E | 전체 메타데이터 리포트 내보내기(.txt) |
| ⇧⌘S | ComfyUI 워크플로우 JSON 저장 |
| ⌘R | Finder에서 보기 |
| ⇧⌘⌫ | 목록 비우기 |

드래그 앤 드롭 외에 Finder의 "열기 방식", 커맨드라인 인자로도 파일을 넘길 수 있습니다. 폴더를 드롭하면 안에 있는 이미지를 한 번에 읽습니다.

## 구조

```
Sources/EXIFViewer/
  App/      앱 진입점, 델리게이트(Finder·CLI 파일 열기), 뷰 모델
  Core/     PNG 청크 리더, ImageIO 추출기, ComfyUI 그래프 파서, 메타데이터 트리
  UI/       테마, 사이드바, 디테일 셸, 5개 탭
tools/makeicon.swift   Resources/AppIcon.icns 생성
build.sh               릴리스 빌드 + .app 번들링 + ad-hoc 서명
```
