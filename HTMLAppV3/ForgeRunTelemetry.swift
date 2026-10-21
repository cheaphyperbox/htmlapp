import Foundation
import SwiftUI

/// Elapsed times are measured from actual phase transitions. Work volume is
/// UTF-8 source bytes; token counts are deliberately described as estimates.
struct ForgeWorkSlice: Codable, Identifiable {
    enum Stage: String, Codable, CaseIterable {
        case prompt, research, search, css, body, script, polish, icon, qa, other

        var label: String {
            switch self {
            case .prompt: return "Improve prompt"
            case .research: return "Research"
            case .search: return "Web search"
            case .css: return "CSS"
            case .body: return "HTML body"
            case .script: return "JavaScript"
            case .polish: return "UI redesign"
            case .icon: return "App icon"
            case .qa: return "App tests"
            case .other: return "Other work"
            }
        }

        var color: Color {
            switch self {
            case .prompt: return .orange
            case .research: return Color(red: 0.57, green: 0.59, blue: 0.63)
            case .search: return .yellow
            case .css: return Color(red: 0.43, green: 0.81, blue: 0.98)
            case .body: return .blue
            case .script: return Color(red: 0.09, green: 0.19, blue: 0.48)
            case .polish: return .pink
            case .icon: return .purple
            case .qa: return .green
            case .other: return .teal
            }
        }
    }

    var id = UUID()
    var stage: Stage
    var startedAt: Date
    var endedAt: Date?
    var sourceBytes: Int

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    var estimatedTokens: Int { sourceBytes == 0 ? 0 : max(1, sourceBytes / 4) }
}

struct ForgeWorkRun: Codable, Identifiable {
    var id = UUID()
    var appKey: String
    var kind: String
    var startedAt: Date
    var endedAt: Date?
    var outcome: String
    var slices: [ForgeWorkSlice]

    var duration: TimeInterval { max(0, (endedAt ?? Date()).timeIntervalSince(startedAt)) }
}

@MainActor
final class ForgeWorkTracker: ObservableObject {
    @Published private(set) var history: [ForgeWorkRun] = []
    @Published private(set) var current: ForgeWorkRun?
    private let storageKey = "htmlapp.forgeWorkHistory.v1"
    private var appKey = "unassigned"
    private var lastPersistAt = Date.distantPast

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ForgeWorkRun].self, from: data) {
            history = decoded
        }
    }

    func select(appKey: String) {
        self.appKey = appKey
    }

    func begin(kind: String, appKey: String) {
        if current != nil { finish(outcome: "Interrupted") }
        self.appKey = appKey
        current = ForgeWorkRun(appKey: appKey, kind: kind, startedAt: Date(),
                               endedAt: nil, outcome: "Running",
                               slices: [ForgeWorkSlice(stage: .prompt, startedAt: Date(),
                                                       endedAt: nil, sourceBytes: 0)])
        persist(force: true)
    }

    func transition(_ stage: ForgeWorkSlice.Stage) {
        guard var run = current, run.slices.last?.stage != stage else { return }
        let now = Date()
        if !run.slices.isEmpty { run.slices[run.slices.count - 1].endedAt = now }
        run.slices.append(ForgeWorkSlice(stage: stage, startedAt: now, endedAt: nil, sourceBytes: 0))
        current = run
        persist(force: true)
    }

    func updateVolume(_ bytes: Int, stage: ForgeWorkSlice.Stage? = nil) {
        guard var run = current, !run.slices.isEmpty else { return }
        let index = stage.flatMap { target in run.slices.lastIndex(where: { $0.stage == target }) }
            ?? run.slices.count - 1
        guard bytes > run.slices[index].sourceBytes else { return }
        run.slices[index].sourceBytes = bytes
        current = run
        persist()
    }

    func observe(phase: String, isBrowsing: Bool, browserStatus: String,
                 streamSection: String) {
        guard current != nil else { return }
        let phrase = (isBrowsing ? browserStatus : phase).lowercased()
        let stage: ForgeWorkSlice.Stage
        if phrase.contains("google") || phrase.contains("search") || phrase.contains("finding") {
            stage = .search
        } else if isBrowsing || phrase.contains("research") || phrase.contains("reading") {
            stage = .research
        } else if phrase.contains("polish") || phrase.contains("redesign") || phrase.contains("overhaul") {
            stage = .polish
        } else if phrase.contains("icon") || phrase.contains("artwork") {
            stage = .icon
        } else if phrase.contains("check") || phrase.contains("review") ||
                    phrase.contains("verif") || phrase.contains("repair") {
            stage = .qa
        } else if phrase.contains("generat") || phrase.contains("coding") ||
                    phrase.contains("patch") || phrase.contains("writing") {
            switch streamSection {
            case "script": stage = .script
            case "body": stage = .body
            default: stage = .css
            }
        } else {
            stage = .prompt
        }
        transition(stage)
    }

    func finish(outcome: String) {
        guard var run = current else { return }
        let now = Date()
        run.endedAt = now
        run.outcome = outcome
        if !run.slices.isEmpty { run.slices[run.slices.count - 1].endedAt = now }
        history.append(run)
        current = nil
        trimAndWrite()
    }

    func associateDraft(with savedAppID: String) {
        guard !savedAppID.isEmpty else { return }
        let key = appKey
        history = history.map { value in
            var copy = value
            if copy.appKey == key { copy.appKey = savedAppID }
            return copy
        }
        if var run = current, run.appKey == key { run.appKey = savedAppID; current = run }
        appKey = savedAppID
        trimAndWrite()
    }

    var recentRuns: [ForgeWorkRun] {
        let past = history.filter { $0.appKey == appKey }.suffix(5)
        if let current { return Array(past) + [current] }
        return Array(past)
    }

    private func persist(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastPersistAt) > 2 else { return }
        lastPersistAt = Date()
        let records = history + (current.map { [$0] } ?? [])
        if let data = try? JSONEncoder().encode(Array(records.suffix(55))) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func trimAndWrite() {
        history = Array(history.suffix(54))
        persist(force: true)
    }
}

/// One ring per entire app lifetime, with each arc proportional to elapsed
/// measured time. Stroke width communicates UTF-8 output size (not exact tokens).
struct ForgeWorkRing: View {
    let runs: [ForgeWorkRun]
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !active)) { context in
            let slices = runs.flatMap(\.slices)
            let times = slices.map { slice in
                max(0.15, (slice.endedAt ?? context.date).timeIntervalSince(slice.startedAt))
            }
            let total = max(0.1, times.reduce(0, +))
            VStack(spacing: 7) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 8)
                    Canvas { canvas, size in
                        let inset: CGFloat = 20
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = max(10, min(size.width, size.height) / 2 - inset)
                        var cursor = -Double.pi / 2
                        for (index, slice) in slices.enumerated() {
                            let proportion = times[index] / total
                            let end = cursor + 2 * Double.pi * proportion
                            let thickness = CGFloat(min(21, max(6, 6 + log2(Double(slice.sourceBytes) / 500 + 1) * 2.7)))
                            var arc = Path()
                            arc.addArc(center: center, radius: radius,
                                       startAngle: .radians(cursor), endAngle: .radians(end),
                                       clockwise: false)
                            let fromCurrent = runs.last?.endedAt == nil &&
                                runs.last?.slices.contains(where: { $0.id == slice.id }) == true
                            canvas.stroke(arc, with: .color(slice.stage.color.opacity(fromCurrent ? 0.66 : 0.98)),
                                          style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                            cursor = end
                        }
                    }
                    VStack(spacing: 2) {
                        Text(formatTime(total))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text(active ? "Working" : "Recorded")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(runs.count) run\(runs.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 166, height: 166)
                .accessibilityLabel("AI task timeline, \(formatTime(total)) across \(runs.count) runs")
                Text("Arc length = time · thickness = text size")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let t = Int(max(0, seconds).rounded())
        return t >= 60 ? "\(t / 60)m \(t % 60)s" : "\(t)s"
    }
}

struct ForgeRunBreakdown: View {
    let runs: [ForgeWorkRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(runs.reversed()) { run in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(run.kind).font(.caption.weight(.semibold))
                        Spacer()
                        Text(run.outcome)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(run.duration))s")
                            .font(.caption.monospacedDigit())
                    }
                    ForEach(run.slices) { slice in
                        HStack(spacing: 7) {
                            Circle().fill(slice.stage.color).frame(width: 8, height: 8)
                            Text(slice.stage.label)
                            Spacer()
                            Text(String(format: "%.1fs", slice.duration))
                                .monospacedDigit()
                            if slice.sourceBytes > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(slice.sourceBytes), countStyle: .file))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Token counts are estimates (~4 bytes/token). The provider may not report actual usage. Timings reflect app-observed stages, not billed model time.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
