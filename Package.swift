// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EXIFViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EXIFViewer",
            path: "Sources/EXIFViewer",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
