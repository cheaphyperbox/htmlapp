import SwiftUI
import WidgetKit
import ActivityKit

@available(iOS 16.2, *)
struct HTMLAppForgeActivityWidget: Widget {
    private let warning = "Do not leave HTMLApp or turn off your phone for more than 20 seconds at a time for now."
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HTMLAppForgeActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 9) {
                Label(context.attributes.isEdit ? "HTMLApp AI Edit" : "HTMLApp AI Generation", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(warning).font(.subheadline.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text("Return to HTMLApp to keep the AI working").font(.caption.weight(.semibold))
                Text(context.state.phase).font(.caption).opacity(0.94)
                ProgressView(value: context.state.progress).tint(.white)
            }
            .foregroundStyle(.white)
            .padding(14)
            .activityBackgroundTint(.red)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "htmlapp://forge"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("HTMLApp", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.isEdit ? "AI edit" : "AI generation").font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(warning).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Text("Return to HTMLApp").font(.caption.weight(.bold))
                        Text(context.state.phase).font(.caption)
                        ProgressView(value: context.state.progress).tint(.red)
                    }
                    .foregroundStyle(.red)
                }
            } compactLeading: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } compactTrailing: {
                Text("HTMLApp").font(.caption2).foregroundStyle(.red)
            } minimal: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            .keylineTint(.red)
            .widgetURL(URL(string: "htmlapp://forge"))
        }
    }
}
