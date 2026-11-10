import Foundation
import AIPulseCore

// aipulse-hook — Claude Code / Codex 훅에서 호출되는 경량 CLI
//
//   aipulse-hook claude|codex          stdin 의 훅 JSON 을 events.jsonl 에 기록 (훅 모드)
//   aipulse-hook install [claude|codex|all]
//   aipulse-hook uninstall [claude|codex|all]
//   aipulse-hook status
//
// 훅 모드 규칙: stdout 에 아무것도 쓰지 않고(일부 이벤트는 stdout 을 컨텍스트로 주입함)
// 어떤 경우에도 exit 0 으로 끝나 에이전트 동작에 영향을 주지 않는다.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? ""

func printUsage() {
    print("""
    사용법:
      aipulse-hook install [claude|codex|all]    훅 등록 (기존 설정은 .aipulse-backup 으로 백업)
      aipulse-hook uninstall [claude|codex|all]  훅 제거
      aipulse-hook status                         등록 상태와 이벤트 로그 위치 확인
      aipulse-hook claude|codex                   (훅 전용) stdin 의 이벤트를 기록
    """)
}

switch command {
case "claude", "codex":
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if let agent = AgentKind(rawValue: command),
       let event = HookInputParser.parse(data: data, agent: agent, env: ProcessInfo.processInfo.environment) {
        try? EventWriter.append(event)
    }
    exit(0)

case "install":
    exit(Installer.run(install: true, target: arguments.dropFirst().first ?? "all"))

case "uninstall":
    exit(Installer.run(install: false, target: arguments.dropFirst().first ?? "all"))

case "status":
    Installer.printStatus()
    exit(0)

case "help", "--help", "-h":
    printUsage()
    exit(0)

default:
    printUsage()
    exit(1)
}
