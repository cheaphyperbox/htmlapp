import SwiftUI
import WidgetKit

/// An always-available Lock Screen launcher, separate from user-published widgets.
struct HTMLAppVoiceCreateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HTMLAppVoiceCreate", provider: Provider()) { _ in
            Content()
        }
        .configurationDisplayName("Speak a New App")
        .description("Open HTMLApp straight to the voice-only AI creation screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }

    struct Entry: TimelineEntry { let date: Date }
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date())) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: Date())], policy: .never))
        }
    }

    struct Content: View {
        @Environment(\.widgetFamily) private var family
        var body: some View {
            Group {
                if family == .accessoryCircular {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if family == .accessoryInline {
                    Label("Speak an app", systemImage: "mic.fill")
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "mic.badge.plus").font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create with Voice").font(.headline).lineLimit(1)
                            Text("Tap to describe an app").font(.caption2).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .widgetURL(URL(string: "htmlapp://voice-create"))
            .modifier(VoiceWidgetBackground())
        }
    }
}

private struct VoiceWidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { Color(.secondarySystemBackground) }
        } else {
            content
        }
    }
}
