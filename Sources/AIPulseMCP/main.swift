import Foundation
import AIPulseCore

// aipulse-mcp — Claude 앱용 MCP 서버 (stdio)
// Claude 데스크톱 앱이 AI Pulse 확장(.mcpb)을 통해 실행한다.
// stdout 은 JSON-RPC 전용이므로 로그는 stderr 로만 쓴다.

let host = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "com.anthropic.claudefordesktop"
MCPServer(hostApp: host).run()
