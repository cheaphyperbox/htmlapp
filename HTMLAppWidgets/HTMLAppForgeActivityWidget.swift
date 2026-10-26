import SwiftUI
import WidgetKit
import ActivityKit

@available(iOS 16.2, *)
struct HTMLAppForgeActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HTMLAppForgeActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                Label(context.attributes.isEdit ? "HTMLApp AI Edit" : "HTMLApp AI Generation",
                      systemImage: "sparkles")
                    .font(.headline)
                Text(context.state.phase)
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: context.state.progress)
                Text("Open HTMLApp to see the current generation step.")
                    .font(.caption)
            }
            .padding(14)
            .activityBackgroundTint(.indigo)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "htmlapp://forge"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("HTMLApp", systemImage: "sparkles")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.isEdit ? "AI edit" : "AI generation")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current step")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.phase)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        ProgressView(value: context.state.progress)
                        Text("\(Int(context.state.progress * 100))% complete")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } minimal: {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            .keylineTint(.indigo)
            .widgetURL(URL(string: "htmlapp://forge"))
        }
    }
}
