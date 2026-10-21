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
                        Text(context.state.value).font(.headline.monospacedDigit())
                    }
                }
                Text(context.state.subtitle)
                    .font(.subheadline)
                    .lineLimit(2)
                if let progress = context.state.progress {
                    ProgressView(value: max(0, min(progress, 1)))
                        .tint(activityAccent(context.state.accentHex))
                }
            }
            .padding(14)
            .activityBackgroundTint(Color(.secondarySystemBackground))
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
                    Text(context.state.value).font(.headline.monospacedDigit()).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.subtitle).font(.subheadline).lineLimit(2)
                        if let progress = context.state.progress {
                            ProgressView(value: max(0, min(progress, 1)))
                                .tint(activityAccent(context.state.accentHex))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.attributes.systemSymbol)
                    .foregroundStyle(activityAccent(context.state.accentHex))
            } compactTrailing: {
                Text(context.state.value.isEmpty ? "•" : context.state.value)
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
