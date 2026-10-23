import Foundation
import SwiftUI
import UIKit

/// A small offline tap-to-catch game. It uses no network or AI calls.
/// Real Forge milestones change the falling shapes, colors, and bonus points,
/// while timed pieces keep play possible during a long model response.
struct ForgeBuildArcadeView: View {
    let milestones: [ForgeBuildMilestone]
    let active: Bool

    @State private var startedAt = Date()
    @State private var captured = Set<Int>()
    @State private var score = 0
    @State private var combo = 0
    @State private var paused = false

    private let spacing: TimeInterval = 0.46
    private let fallDuration: TimeInterval = 2.6
    private let lanes = 5

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Tap falling shapes", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Score \(score)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                if combo > 1 {
                    Text("×\(combo)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Button { resetGame() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Restart game")
                Button {
                    paused.toggle()
                    if !paused { resetGame() }
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(paused ? "Play a new game" : "Pause game")
            }
            .padding(.horizontal, 10)

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: paused || !active)) { context in
                GeometryReader { proxy in
                    let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                    Canvas { canvas, size in
                        let laneWidth = size.width / CGFloat(lanes)
                        // Soft column guides keep hit areas easy to discover.
                        for lane in 0..<lanes {
                            let rect = CGRect(x: CGFloat(lane) * laneWidth + 3, y: 0,
                                              width: laneWidth - 6, height: size.height)
                            canvas.fill(Path(roundedRect: rect, cornerRadius: 12),
                                        with: .color(Color.primary.opacity(0.035)))
                        }
                        let upper = max(0, Int(elapsed / spacing))
                        let lower = max(0, upper - 7)
                        for id in lower...upper {
                            guard !captured.contains(id) else { continue }
                            guard let block = piece(id: id, elapsed: elapsed, size: size) else { continue }
                            let color = colorForBlock(id)
                            for (cx, cy) in patternForBlock(id) {
                                let unit = block.width / 3.2
                                let rect = CGRect(
                                    x: block.x + CGFloat(cx) * unit,
                                    y: block.y + CGFloat(cy) * unit,
                                    width: unit - 2, height: unit - 2
                                )
                                canvas.fill(Path(roundedRect: rect, cornerRadius: 4),
                                            with: .color(color))
                                canvas.stroke(Path(roundedRect: rect, cornerRadius: 4),
                                              with: .color(.white.opacity(0.4)), lineWidth: 0.75)
                            }
                        }
                        canvas.fill(Path(CGRect(x: 0, y: size.height - 5,
                                                width: size.width, height: 5)),
                                    with: .color(Color.accentColor.opacity(0.35)))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { gesture in
                            guard !paused && active else { return }
                            let now = max(0, Date().timeIntervalSince(startedAt))
                            let upper = max(0, Int(now / spacing))
                            let lower = max(0, upper - 7)
                            for id in (lower...upper).reversed() {
                                guard !captured.contains(id),
                                      let block = piece(id: id, elapsed: now, size: proxy.size) else { continue }
                                let touch = gesture.location
                                if CGRect(x: block.x - 22, y: block.y - 42,
                                          width: block.width + 44,
                                          height: block.width + 84).contains(touch) {
                                    captured.insert(id)
                                    combo = min(combo + 1, 9)
                                    // Tied to real milestones, with small idle targets.
                                    let sizeBonus = milestones.isEmpty ? 0 :
                                        min(4, max(0, milestones[min(id % milestones.count, milestones.count - 1)].bytes / 4000))
                                    score += 10 + combo * 5 + sizeBonus
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    return
                                }
                            }
                            combo = 0
                        }
                    )
                }
            }
            .frame(height: 230)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .clipped()

            HStack(spacing: 5) {
                Image(systemName: "hand.tap")
                Text("Tap falling shapes to catch them. Chain catches for bonus points. Restart with ↻ or pause anytime.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
        }
        .onChange(of: active) { running in
            if running && paused { resetGame() }
        }
    }

    private func resetGame() {
        startedAt = Date()
        captured = []
        score = 0
        combo = 0
        paused = false
    }

    private func piece(id: Int, elapsed: TimeInterval, size: CGSize)
        -> (x: CGFloat, y: CGFloat, width: CGFloat)? {
        let age = elapsed - Double(id) * spacing
        guard age >= 0 && age <= fallDuration else { return nil }
        let laneWidth = size.width / CGFloat(lanes)
        let lane = (id * 7 + id / 3) % lanes
        let magnitude = milestones.isEmpty ? 0 : milestones[id % milestones.count].bytes
        let width = min(laneWidth - 13, CGFloat(magnitude > 5000 ? 55 : 43))
        let x = CGFloat(lane) * laneWidth + (laneWidth - width) * 0.5
        let progress = CGFloat(age / fallDuration)
        let y = -width + progress * (size.height + width)
        return (x, y, width)
    }

    private func patternForBlock(_ id: Int) -> [(Int, Int)] {
        if !milestones.isEmpty {
            let milestone = milestones[id % milestones.count]
            if milestone.bytes > 5000 { return [(0,0),(1,0),(2,0),(1,1),(1,2)] }
            if milestone.kind == .script || milestone.kind == .website {
                return [(0,0),(0,1),(1,1),(2,1)]
            }
        }
        switch id % 4 {
        case 0: return [(0,0),(1,0),(1,1),(2,1)]
        case 1: return [(0,0),(1,0),(2,0),(1,1)]
        case 2: return [(0,0),(0,1),(1,1),(1,2)]
        default: return [(0,0),(1,0),(0,1),(1,1)]
        }
    }

    private func colorForBlock(_ id: Int) -> Color {
        guard !milestones.isEmpty else { return .blue }
        switch milestones[id % milestones.count].kind {
        case .plan: return .purple
        case .api: return .cyan
        case .website: return .mint
        case .head: return .orange
        case .body: return .pink
        case .script: return .blue
        case .icon: return .yellow
        case .test, .finished: return .green
        }
    }
}
