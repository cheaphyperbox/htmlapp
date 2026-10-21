import Foundation
import SwiftUI

/// Milestones are derived from actual completed work, never from fabricated percentages.
struct ForgeBuildMilestone: Identifiable, Equatable {
    enum Kind: String {
        case plan, api, website, head, body, script, icon, test, finished
    }
    let id: UUID
    let kind: Kind
    let title: String
    let bytes: Int
    let at: Date

    init(kind: Kind, title: String, bytes: Int = 0) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.bytes = bytes
        self.at = Date()
    }
}

@MainActor
final class ForgeBuildMilestones: ObservableObject {
    @Published private(set) var events: [ForgeBuildMilestone] = []
    private var seen = Set<String>()

    func reset() {
        events = []
        seen = []
    }

    func add(_ kind: ForgeBuildMilestone.Kind, _ title: String, bytes: Int = 0, key: String? = nil) {
        let unique = key ?? kind.rawValue + ":" + title
        guard seen.insert(unique).inserted else { return }
        events.append(ForgeBuildMilestone(kind: kind, title: title, bytes: bytes))
        if events.count > 24 { events.removeFirst(events.count - 24) }
    }

    func inspectHTML(_ html: String) {
        // The opening sections may already be streamed; only count a closed section.
        func section(_ open: String, _ close: String) -> Int? {
            guard let first = html.range(of: open, options: .caseInsensitive),
                  let last = html.range(of: close, options: .caseInsensitive, range: first.upperBound..<html.endIndex) else { return nil }
            return html[first.lowerBound..<last.upperBound].utf8.count
        }
        if let bytes = section("<head", "</head>") {
            add(.head, "HTML head ready", bytes: bytes, key: "html-head")
        }
        if let bytes = section("<body", "</body>") {
            add(.body, "App interface ready", bytes: bytes, key: "html-body")
        }
        if let bytes = section("<script", "</script>") {
            add(.script, "App logic ready", bytes: bytes, key: "html-script")
        }
    }
}

/// A playful, deterministic gravity simulation. Block mass/size is derived from
/// real source lengths; each completed stage drops one polyomino with a bounce.
struct ForgeFallingBlocksView: View {
    let milestones: [ForgeBuildMilestone]
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            Canvas { graphics, size in
                // Small dim pieces keep the scene alive during long model
                // responses. Only opaque, named pieces represent actual milestones.
                if active, let beginning = milestones.first?.at {
                    let seconds = max(0, timeline.date.timeIntervalSince(beginning))
                    let last = Int(seconds / 0.42)
                    for tick in max(0, last - 9)...last {
                        let age = seconds - Double(tick) * 0.42
                        guard age >= 0, age < 3.7 else { continue }
                        let width: CGFloat = CGFloat(8 + (tick % 3) * 3)
                        let x = CGFloat((tick * 43 + 17) % max(1, Int(size.width - width)))
                        let y = CGFloat(-16 + age * 112)
                        let rect = CGRect(x: x, y: y, width: width, height: width)
                        graphics.fill(Path(roundedRect: rect, cornerRadius: 3),
                                      with: .color(Color.accentColor.opacity(0.10)))
                    }
                }
                let laneWidth = max(20, size.width / 7)
                let columnCount = max(1, Int(size.width / laneWidth))
                for (index, milestone) in milestones.enumerated() {
                    let age = max(0, timeline.date.timeIntervalSince(milestone.at))
                    let scale = CGFloat(min(1.40, max(0.55, 0.58 + log2(Double(max(512, milestone.bytes)) / 512.0 + 1) * 0.11)))
                    let cell = max(8, min(19, laneWidth * 0.43)) * scale
                    let cells = shape(for: milestone.kind, bytes: milestone.bytes)
                    let width = CGFloat((cells.map { $0.0 }.max() ?? 0) + 1) * cell
                    let height = CGFloat((cells.map { $0.1 }.max() ?? 0) + 1) * cell
                    let lane = (index * 3 + 1) % columnCount
                    let x = min(max(4, CGFloat(lane) * laneWidth + (laneWidth - width) / 2), max(4, size.width - width - 4))
                    let row = CGFloat(index / columnCount)
                    let restingY = max(2, size.height - height - 7 - row * cell * 2.35)
                    // Gravity with a damped restitution oscillation after impact.
                    let descent = CGFloat(0.5 * 740 * age * age)
                    let impact = sqrt(2 * Double(max(1, restingY + height + 12)) / 740)
                    let y: CGFloat
                    if age < impact {
                        y = -height - 12 + descent
                    } else {
                        let t = CGFloat(age - impact)
                        let bounce = CGFloat(abs(sin(Double(t * 10))) * exp(Double(-t * 4.2))) * 33 * scale
                        y = restingY - bounce
                    }
                    let hue = tint(milestone.kind)
                    for (cx, cy) in cells {
                        let rect = CGRect(x: x + CGFloat(cx) * cell, y: min(restingY, y) + CGFloat(cy) * cell,
                                          width: cell - 2, height: cell - 2)
                        guard rect.maxY >= 0, rect.minY <= size.height else { continue }
                        let path = Path(roundedRect: rect, cornerRadius: max(2, cell * 0.17))
                        graphics.fill(path, with: .color(hue))
                        graphics.stroke(path, with: .color(.white.opacity(0.33)), lineWidth: 0.8)
                    }
                }
                let base = CGRect(x: 0, y: size.height - 3, width: size.width, height: 3)
                graphics.fill(Path(base), with: .color(.secondary.opacity(0.20)))
            }
        }
        .accessibilityHidden(true)
    }

    private func tint(_ kind: ForgeBuildMilestone.Kind) -> Color {
        switch kind {
        case .plan: return Color(red: 0.56, green: 0.46, blue: 0.86)
        case .api: return Color(red: 0.32, green: 0.62, blue: 0.87)
        case .website: return Color(red: 0.22, green: 0.69, blue: 0.62)
        case .head: return Color(red: 0.93, green: 0.61, blue: 0.35)
        case .body: return Color(red: 0.88, green: 0.42, blue: 0.53)
        case .script: return Color(red: 0.40, green: 0.63, blue: 0.92)
        case .icon: return Color(red: 0.93, green: 0.75, blue: 0.33)
        case .test: return Color(red: 0.42, green: 0.75, blue: 0.48)
        case .finished: return .mint
        }
    }

    private func shape(for kind: ForgeBuildMilestone.Kind, bytes: Int) -> [(Int, Int)] {
        // Bigger source/page milestones grow into richer polyomino shapes.
        let magnitude = max(0, bytes)
        if magnitude > 14_000 {
            return [(0,0),(1,0),(2,0),(1,1),(1,2),(2,2)]
        }
        if magnitude > 5_000 {
            return [(0,0),(1,0),(2,0),(0,1),(0,2)]
        }
        if magnitude > 1_400 {
            return [(0,0),(1,0),(1,1),(2,1)]
        }
        switch kind {
        case .plan, .head: return [(0,0),(1,0),(1,1)]
        case .api, .script: return [(0,0),(1,0),(2,0),(1,1)]
        case .website, .icon: return [(0,0),(0,1),(1,1)]
        case .body: return [(0,0),(1,0),(0,1),(1,1)]
        case .test, .finished: return [(0,0),(0,1),(1,1)]
        }
    }
}

struct ForgeBuildDashboard: View {
    let title: String
    let explanation: String
    let milestones: [ForgeBuildMilestone]
    let active: Bool
    let bytes: Int
    let runs: [ForgeWorkRun]
    @State private var playGame = true
    @State private var showNumbers = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                if active { ProgressView().controlSize(.regular) }
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(explanation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                }
            }
            .padding(.horizontal, 18)

            HStack(alignment: .center, spacing: 13) {
                ForgeWorkRing(runs: runs, active: active)
                    .frame(width: 178)
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI activity")
                        .font(.subheadline.weight(.semibold))
                    if let stage = runs.last?.slices.last {
                        HStack(spacing: 6) {
                            Circle().fill(stage.stage.color).frame(width: 8, height: 8)
                            Text(stage.stage.label).font(.subheadline.weight(.medium))
                        }
                    }
                    Text("Colors show each task. Larger arcs took longer; thicker arcs produced more text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)

            DisclosureGroup("Compare time and text per task", isExpanded: $showNumbers) {
                ForgeRunBreakdown(runs: runs).padding(.vertical, 6)
            }
            .font(.subheadline)
            .padding(.horizontal, 18)

            HStack {
                Text(playGame ? "Play while Forge works" : "Watch Forge's work")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { playGame.toggle() }
                } label: {
                    Label(playGame ? "Watch Blocks" : "Play Game",
                          systemImage: playGame ? "square.stack.3d.up" : "gamecontroller.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 18)

            Group {
                if playGame {
                    ForgeBuildArcadeView(milestones: milestones, active: active)
                        .padding(10)
                } else {
                    ForgeFallingBlocksView(milestones: milestones, active: active)
                        .frame(height: 235)
                        .overlay(alignment: .topLeading) {
                            Text("Completed milestones")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(12)
                        }
                }
            }
            .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 12)

            if let recent = milestones.last {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(recent.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if recent.bytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(recent.bytes), countStyle: .file))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .accessibilityElement(children: .combine)
            }
            if bytes > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) generated")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }
            Text("The game keeps moving between real AI milestones. Only named milestones indicate completed work.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
        .padding(.top, 14)
        }
    }
}
