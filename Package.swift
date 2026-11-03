// swift-tools-version: 5.9
import PackageDescription

// 仅用于在本机验证核心节拍数学（无 UI / 无音频依赖）。
// iOS App 本体走 PianoMetronome.xcodeproj，两者共用 Metronome/Core 下的同一批源文件。
let package = Package(
    name: "MetronomeCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "MetronomeCore", targets: ["MetronomeCore"])
    ],
    targets: [
        .target(
            name: "MetronomeCore",
            path: "Metronome/Core"
        ),
        .testTarget(
            name: "MetronomeCoreTests",
            dependencies: ["MetronomeCore"],
            path: "Tests"
        )
    ]
)
