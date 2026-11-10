// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIPulse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIPulse", targets: ["AIPulse"]),
        .executable(name: "aipulse-hook", targets: ["AIPulseHook"]),
        .executable(name: "aipulse-mcp", targets: ["AIPulseMCP"]),
        .library(name: "AIPulseCore", targets: ["AIPulseCore"]),
    ],
    targets: [
        // UI와 무관한 순수 로직: 이벤트 모델, 훅 입력 파서, 상태 리듀서, 로그 테일러, 데모 스크립트
        .target(name: "AIPulseCore"),
        // 메뉴바 앱 (SwiftUI + AppKit)
        .executableTarget(name: "AIPulse", dependencies: ["AIPulseCore"]),
        // Claude Code / Codex 훅에서 호출되는 경량 CLI
        .executableTarget(name: "AIPulseHook", dependencies: ["AIPulseCore"]),
        // Claude 데스크톱 앱 확장(.mcpb)이 실행하는 MCP 서버
        .executableTarget(name: "AIPulseMCP", dependencies: ["AIPulseCore"]),
        .testTarget(name: "AIPulseCoreTests", dependencies: ["AIPulseCore"]),
    ]
)
