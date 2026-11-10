import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum PulsePaths {
    /// ~/Library/Application Support/AIPulse  (AIPULSE_HOME 환경변수로 재지정 가능 — 테스트용)
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["AIPULSE_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AIPulse", isDirectory: true)
    }

    public static var eventsFile: URL {
        supportDirectory.appendingPathComponent("events.jsonl")
    }
}

/// 훅 프로세스 쪽: 이벤트 한 줄을 O_APPEND 단일 write 로 기록 (여러 세션이 동시에 써도 줄이 섞이지 않음)
public enum EventWriter {
    public static func append(_ event: PulseEvent, to url: URL = PulsePaths.eventsFile) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = try encoder.encode(event)
        data.append(0x0A)

        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return write(fd, base, buffer.count)
        }
        if written != data.count { throw CocoaError(.fileWriteUnknown) }
    }
}

/// 앱 쪽: events.jsonl 을 tail 하며 새 줄만 읽는다.
public final class EventTailer {
    public let url: URL
    private let initialReplayBytes: UInt64
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var started = false
    private var skipPartialFirstLine = false
    private let decoder = JSONDecoder()

    public init(url: URL, initialReplayBytes: UInt64 = 2_000_000) {
        self.url = url
        self.initialReplayBytes = initialReplayBytes
    }

    private func fileSize() -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attrs[.size] as? NSNumber)?.uint64Value
    }

    /// 마지막 호출 이후 추가된 이벤트. 첫 호출은 최근 기록(initialReplayBytes)을 재생해 진행 중 세션을 복원한다.
    public func readNew() -> [PulseEvent] {
        guard let size = fileSize() else { return [] }

        if !started {
            started = true
            if size > initialReplayBytes {
                offset = size - initialReplayBytes
                skipPartialFirstLine = true
            }
        }
        if size < offset {
            // 파일이 잘렸거나 교체됨
            offset = 0
            remainder.removeAll()
            skipPartialFirstLine = false
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let chunk: Data
        do {
            try handle.seek(toOffset: offset)
            chunk = try handle.readToEnd() ?? Data()
        } catch {
            return []
        }
        offset += UInt64(chunk.count)

        var buffer = remainder
        buffer.append(chunk)
        if skipPartialFirstLine {
            guard let newline = buffer.firstIndex(of: 0x0A) else {
                remainder = buffer
                return []
            }
            buffer = Data(buffer[buffer.index(after: newline)...])
            skipPartialFirstLine = false
        }

        var events: [PulseEvent] = []
        var lineStart = buffer.startIndex
        while lineStart < buffer.endIndex, let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
            let line = buffer[lineStart..<newline]
            if !line.isEmpty, let event = try? decoder.decode(PulseEvent.self, from: Data(line)) {
                events.append(event)
            }
            lineStart = buffer.index(after: newline)
        }
        remainder = Data(buffer[lineStart...])
        return events
    }

    /// 로그가 커지면 비운다 (모든 줄을 읽은 직후에만).
    public func compactIfNeeded(maxBytes: UInt64 = 8_000_000) {
        guard offset >= maxBytes, remainder.isEmpty,
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: 0)
            offset = 0
        } catch {
            // 다음 기회에 다시 시도
        }
    }
}
