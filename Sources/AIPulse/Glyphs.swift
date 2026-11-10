import SwiftUI
import AIPulseCore

/// 상태별 캐릭터/아이콘. 테마마다 그리는 방식만 다르고 상태 의미는 같다.
/// - 움직임 줄이기(접근성)가 켜져 있거나 animated == false 이면 정지 프레임만 그린다.
/// - 완료 상태는 정지 이미지라 타임라인을 멈춰 CPU 를 쓰지 않는다.
struct StatusGlyph: View {
    let state: ActivityState
    var size: CGFloat = 24
    var animated: Bool = true

    @Environment(\.pulseTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Bool { animated && !reduceMotion && state != .done }

    private var frameInterval: Double {
        switch theme.kind {
        case .retroPixel: return 1.0 / 8      // 계단식
        default: return state == .idle ? 1.0 / 12 : 1.0 / 30
        }
    }

    var body: some View {
        let color = theme.color(for: state)
        TimelineView(.animation(minimumInterval: frameInterval, paused: !motion)) { context in
            let t = motion ? context.date.timeIntervalSinceReferenceDate : 0
            glyph(t: t, color: color)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(state.label)
    }

    @ViewBuilder
    private func glyph(t: Double, color: Color) -> some View {
        switch theme.kind {
        case .appleMinimal, .warmGlass:
            VectorGlyph(state: state, t: t, color: color, size: size, glow: false)
        case .neon:
            VectorGlyph(state: state, t: t, color: color, size: size, glow: true)
        case .retroPixel:
            PixelGlyph(state: state, t: t, color: color, size: size)
        case .animal:
            AnimalGlyph(state: state, t: t, color: color, size: size)
        }
    }
}

// MARK: - Apple Minimal / Neon

struct VectorGlyph: View {
    let state: ActivityState
    let t: Double
    let color: Color
    let size: CGFloat
    let glow: Bool

    private var line: CGFloat { max(1.5, size * (glow ? 0.1 : 0.08)) }

    var body: some View {
        content
            .frame(width: size, height: size)
            .shadow(color: glow ? color.opacity(0.9) : .clear, radius: glow ? size * 0.15 : 0)
            .shadow(color: glow ? color.opacity(0.45) : .clear, radius: glow ? size * 0.35 : 0)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            // 천천히 호흡
            let breath = 0.5 + 0.5 * sin(t * 1.6)
            Circle()
                .fill(color.opacity(0.3 + 0.35 * breath))
                .frame(width: size * (0.4 + 0.12 * breath), height: size * (0.4 + 0.12 * breath))

        case .thinking:
            // 회전 링
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: line)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(t * 300))
                Circle()
                    .fill(color)
                    .frame(width: size * 0.18, height: size * 0.18)
                    .opacity(0.55 + 0.45 * sin(t * 3))
            }
            .padding(line / 2)

        case .writing:
            // 타이핑 인디케이터
            HStack(alignment: .bottom, spacing: size * 0.08) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: size * 0.16, height: size * (0.2 + 0.32 * max(0, sin(t * 7 - Double(i) * 0.9))))
                }
            }
            .frame(height: size * 0.6, alignment: .bottom)

        case .testing:
            // 스캔 + 점등
            let active = Int(t * 4) % 4
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .stroke(color.opacity(0.35), lineWidth: line * 0.7)
                VStack(spacing: size * 0.1) {
                    HStack(spacing: size * 0.1) { lamp(0, active); lamp(1, active) }
                    HStack(spacing: size * 0.1) { lamp(3, active); lamp(2, active) }
                }
                Rectangle()
                    .fill(color.opacity(0.55))
                    .frame(height: 1.2)
                    .offset(y: size * 0.3 * sin(t * 2.4))
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .padding(line / 2)

        case .awaitingApproval:
            // 주황색 펄스
            let p = (t * 0.9).truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle()
                    .stroke(color.opacity(1 - p), lineWidth: line * 0.8)
                    .scaleEffect(0.55 + 0.45 * p)
                Circle()
                    .fill(color)
                    .frame(width: size * 0.52, height: size * 0.52)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(.white)
            }

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size * 0.84, weight: .semibold))
                .foregroundStyle(color)

        case .error:
            // 빨간색 경고 점멸
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(color)
                .opacity(0.55 + 0.45 * abs(sin(t * 3)))
        }
    }

    private func lamp(_ index: Int, _ active: Int) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color.opacity(index == active ? 1 : 0.22))
            .frame(width: size * 0.2, height: size * 0.2)
    }
}

// MARK: - Retro Pixel

struct PixelGlyph: View {
    let state: ActivityState
    let t: Double
    let color: Color
    let size: CGFloat

    private var frame: Int {
        switch state {
        case .idle: return Int(t * 1.2) % 4 == 3 ? 1 : 0     // 가끔 깜빡임
        default: return Int(t * 3) % 2
        }
    }

    var body: some View {
        let frame = self.frame
        let scan = Int(t * 6) % 6
        let face = PixelFaces.face(for: state, frame: frame, scan: scan)
        let bodyColor = (state == .error && frame == 1) ? color.opacity(0.5) : color
        let hop: CGFloat = (state == .writing || state == .awaitingApproval) && frame == 1 ? -1 : 0

        Canvas { ctx, canvasSize in
            let px = max(1, floor(min(canvasSize.width, canvasSize.height) / 8))
            let ox = (canvasSize.width - px * 8) / 2
            let oy = (canvasSize.height - px * 8) / 2
            for y in 0..<8 {
                for x in 0..<8 {
                    let corner = (x == 0 || x == 7) && (y == 0 || y == 7)
                    if corner { continue }
                    let rect = CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px, height: px)
                    ctx.fill(Path(rect), with: .color(bodyColor))
                }
            }
            for (y, row) in face.enumerated() {
                for (x, ch) in row.enumerated() where ch == "o" {
                    let rect = CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px, height: px)
                    ctx.fill(Path(rect), with: .color(.black.opacity(0.78)))
                }
            }
        }
        .offset(y: hop)
    }
}

enum PixelFaces {
    static func face(for state: ActivityState, frame: Int, scan: Int) -> [String] {
        switch state {
        case .idle:
            return frame == 0
                ? ["........", "..o..o..", "..o..o..", "........", "........", "...oo...", "........", "........"]
                : ["........", "........", ".oo..oo.", "........", "........", "...oo...", "........", "........"]
        case .thinking:
            return frame == 0
                ? ["........", ".oo.oo..", ".oo.oo..", "........", "........", "...ooo..", "........", "........"]
                : ["........", "..oo.oo.", "..oo.oo.", "........", "........", "..ooo...", "........", "........"]
        case .writing:
            return frame == 0
                ? ["........", "..o..o..", "..o..o..", "........", "........", ".o.o.o..", "........", "........"]
                : ["........", "..o..o..", "..o..o..", "........", "........", "..o.o.o.", "........", "........"]
        case .testing:
            let visor = String((0..<8).map { (col: Int) -> Character in col == scan + 1 ? "o" : "." })
            return ["........", "........", visor, "........", "........", "..oooo..", "........", "........"]
        case .awaitingApproval:
            return frame == 0
                ? ["...oo...", "...oo...", "...oo...", "...oo...", "........", "...oo...", "........", "........"]
                : ["........", "..o..o..", "..o..o..", "........", "...oo...", "...oo...", "........", "........"]
        case .done:
            return ["........", "..o..o..", ".o.oo.o.", "........", ".o....o.", "..oooo..", "........", "........"]
        case .error:
            return ["........", ".o.oo.o.", "..o..o..", ".o.oo.o.", "........", "..oooo..", ".o....o.", "........"]
        }
    }
}

// MARK: - Animal

struct AnimalGlyph: View {
    let state: ActivityState
    let t: Double
    let color: Color
    let size: CGFloat

    private var emoji: String {
        switch state {
        case .idle: return "😺"
        case .thinking: return "😼"
        case .writing: return "😸"
        case .testing: return "😺"
        case .awaitingApproval: return "😾"
        case .done: return "😻"
        case .error: return "🙀"
        }
    }

    /// (dx, dy, 회전 각도, 배율)
    private var pose: (CGFloat, CGFloat, Double, CGFloat) {
        switch state {
        case .idle: return (0, 0, 0, 1 + 0.05 * CGFloat(sin(t * 1.6)))
        case .thinking: return (0, 0, 10 * sin(t * 2), 1)
        case .writing: return (0, -CGFloat(abs(sin(t * 9))) * size * 0.07, 0, 1)
        case .testing: return (CGFloat(sin(t * 3)) * size * 0.08, 0, 0, 1)
        case .awaitingApproval: return (0, 0, 0, 1 + 0.1 * CGFloat(abs(sin(t * 3))))
        case .done: return (0, 0, 0, 1)
        case .error: return (CGFloat(sin(t * 30)) * size * 0.04 * (sin(t * 2) > 0 ? 1 : 0), 0, 0, 1)
        }
    }

    var body: some View {
        let p = pose
        ZStack {
            Circle().fill(color.opacity(0.3))
            Text(emoji)
                .font(.system(size: size * 0.62))
                .scaleEffect(p.3)
                .rotationEffect(.degrees(p.2))
                .offset(x: p.0, y: p.1)
        }
    }
}

// MARK: - Progress

/// 근거 있는 진행률이 있으면 막대, 없으면 활동 표시(움직이는 구간)만 보여준다.
struct PulseProgressBar: View {
    let value: Double?
    let state: ActivityState
    var animated: Bool = true

    @Environment(\.pulseTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat {
        switch theme.kind {
        case .retroPixel, .animal: return 6
        case .warmGlass, .neon: return 7
        default: return 4
        }
    }

    var body: some View {
        let color = theme.color(for: state)
        Group {
            if let value {
                determinate(min(1, max(0, value)), color: color)
            } else {
                indeterminate(color)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func determinate(_ value: Double, color: Color) -> some View {
        if theme.kind == .retroPixel {
            HStack(spacing: 1) {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle().fill(Double(i) < value * 12 ? color : theme.trackColor)
                }
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.trackColor)
                    Capsule()
                        .fill(LinearGradient(colors: theme.progressFill(for: state), startPoint: .leading, endPoint: .trailing))
                        .frame(width: value <= 0 ? 0 : max(height, geo.size.width * value))
                        .shadow(color: (theme.progressFill(for: state).last ?? color).opacity(theme.glow || theme.customPanel ? 0.7 : 0),
                                radius: theme.glow || theme.customPanel ? 5 : 0)
                }
            }
            .animation(.easeOut(duration: 0.35), value: value)
        }
    }

    @ViewBuilder
    private func indeterminate(_ color: Color) -> some View {
        let motion = animated && !reduceMotion && state.isActive
        if !state.isActive {
            Capsule().fill(theme.trackColor)
        } else if !motion {
            Capsule().fill(color.opacity(0.35))
        } else {
            TimelineView(.animation(minimumInterval: theme.kind == .retroPixel ? 1.0 / 8 : 1.0 / 30)) { context in
                let raw = (context.date.timeIntervalSinceReferenceDate * 0.7).truncatingRemainder(dividingBy: 1)
                let phase = theme.kind == .retroPixel ? (raw * 8).rounded(.down) / 8 : raw
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.trackColor)
                        Capsule()
                            .fill(LinearGradient(colors: theme.progressFill(for: state), startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: geo.size.width * 1.3 * phase - geo.size.width * 0.3)
                            .shadow(color: theme.glow ? color : .clear, radius: theme.glow ? 3 : 0)
                    }
                    .clipShape(Capsule())
                }
            }
        }
    }
}
