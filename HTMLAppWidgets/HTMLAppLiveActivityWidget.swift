import WidgetKit
import SwiftUI
import ActivityKit

@available(iOS 16.2, *)
struct HTMLAppLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HTMLAppLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: context.attributes.systemSymbol)
                        .foregroundStyle(activityAccent(context.state.accentHex))
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !context.state.value.isEmpty {
                        Group {
                            if let deadline = context.state.primaryDeadline {
                                Text(timerInterval: Date.distantPast...deadline, countsDown: true)
                            } else {
                                Text(context.state.value)
                            }
                        }.font(.headline.monospacedDigit())
                    }
                }
                Group {
                    if let deadline = context.state.primaryDeadline {
                        HStack(spacing: 5) {
                            Text("Start in")
                            Text(deadline, style: .timer)
                        }
                    } else { Text(context.state.subtitle) }
                }
                    .font(.subheadline)
                    .lineLimit(2)
                if let second = context.state.secondaryValue, !second.isEmpty {
                    HStack(spacing: 8) {
                        Text(context.state.secondaryLabel ?? "Details")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Group {
                            if let deadline = context.state.secondaryDeadline {
                                Text(deadline, style: .timer)
                            } else { Text(second) }
                        }.font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
                if let progress = context.state.progress {
                    ProgressView(value: max(0, min(progress, 1)))
                        .tint(activityAccent(context.state.accentHex))
                }
                if let footer = context.state.footer, !footer.isEmpty {
                    Text(footer).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .activityBackgroundTint(context.state.backgroundHex.map { activityAccent($0) } ?? Color(.secondarySystemBackground))
            .activitySystemActionForegroundColor(activityAccent(context.state.accentHex))
            .widgetURL(activityURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.systemSymbol)
                        .foregroundStyle(activityAccent(context.state.accentHex))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if let deadline = context.state.primaryDeadline {
                            Text(deadline, style: .timer)
                        } else { Text(context.state.value) }
                    }.font(.headline.monospacedDigit()).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.subtitle).font(.subheadline).lineLimit(2)
                        if let progress = context.state.progress {
                            ProgressView(value: max(0, min(progress, 1)))
                                .tint(activityAccent(context.state.accentHex))
                        }
                        if let secondary = context.state.secondaryValue, !secondary.isEmpty {
                            HStack(spacing: 6) {
                                Text(context.state.secondaryLabel ?? "Details").foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Group {
                                    if let deadline = context.state.secondaryDeadline {
                                        Text(deadline, style: .timer)
                                    } else { Text(secondary) }
                                }.fontWeight(.semibold)
                            }
                            .font(.caption)
                        }
                        if let footer = context.state.footer, !footer.isEmpty {
                            Text(footer).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.attributes.systemSymbol)
                    .foregroundStyle(activityAccent(context.state.accentHex))
            } compactTrailing: {
                Group {
                    if let deadline = context.state.primaryDeadline {
                        Text(deadline, style: .timer)
                    } else {
                        Text((context.state.compactLabel?.isEmpty == false ? context.state.compactLabel : nil) ?? (context.state.value.isEmpty ? "•" : context.state.value))
                    }
                }
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            } minimal: {
                Image(systemName: context.attributes.systemSymbol)
                    .foregroundStyle(activityAccent(context.state.accentHex))
            }
            .widgetURL(activityURL(context.attributes))
        }
    }

    private func activityURL(_ attributes: HTMLAppLiveActivityAttributes) -> URL? {
        var parts = URLComponents()
        parts.scheme = "htmlapp"
        parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "id", value: attributes.appID)]
        return parts.url
    }

    private func activityAccent(_ hex: String) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .accentColor }
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}
