import WidgetKit
import SwiftUI
import AppIntents
import UIKit

struct HTMLAppWidgetEntry: TimelineEntry {
    let date: Date
    let definition: HTMLAppWidgetDefinition
}

struct HTMLAppPrimaryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HTMLAppWidgetEntry {
        .init(date: Date(), definition: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (HTMLAppWidgetEntry) -> Void) {
        completion(.init(date: Date(), definition: HTMLAppWidgetStore.preferredDefinition() ?? (HTMLAppSharedContainer.appGroupAvailable ? .placeholder() : .unavailable())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HTMLAppWidgetEntry>) -> Void) {
        Task {
            var definition = HTMLAppWidgetStore.preferredDefinition() ?? (HTMLAppSharedContainer.appGroupAvailable ? .placeholder() : .unavailable())
            definition = await HTMLAppWidgetNetwork.refreshed(definition)
            if definition.appID != "placeholder" {
                HTMLAppWidgetStore.save(definition)
            }
            let interval = definition.refresh.map { max(15, $0.intervalMinutes) } ?? 60
            let next = Date().addingTimeInterval(TimeInterval(interval * 60))
            completion(Timeline(entries: [.init(date: Date(), definition: definition)], policy: .after(next)))
        }
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "HTMLApp Widget"
    static var defaultQuery = HTMLAppWidgetEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetEntityQuery: EntityQuery {
    private var choices: [HTMLAppWidgetEntity] {
        let available = HTMLAppWidgetStore.all().map {
            HTMLAppWidgetEntity(id: $0.id, name: $0.name)
        }
        if available.isEmpty {
            return [HTMLAppWidgetEntity(
                id: "htmlapp-no-widgets",
                name: HTMLAppSharedContainer.appGroupAvailable
                    ? "No published widgets — open HTMLApp"
                    : "Widget App Group missing — check signing"
            )]
        }
        return available
    }

    func entities(for identifiers: [HTMLAppWidgetEntity.ID]) async throws -> [HTMLAppWidgetEntity] {
        let wanted = Set(identifiers)
        return choices.filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HTMLAppWidgetEntity] {
        choices
    }

    func defaultResult() async -> HTMLAppWidgetEntity? {
        choices.first
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose HTMLApp Widget"
    static var description = IntentDescription("Choose a widget published by one of your saved HTMLApps.")

    @Parameter(title: "Widget")
    var widget: HTMLAppWidgetEntity?
}

@available(iOS 17.0, *)
struct HTMLAppConfiguredWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HTMLAppWidgetEntry {
        .init(date: Date(), definition: .placeholder())
    }

    func snapshot(for configuration: HTMLAppWidgetConfigurationIntent, in context: Context) async -> HTMLAppWidgetEntry {
        .init(date: Date(), definition: selected(configuration) ?? .placeholder())
    }

    func timeline(for configuration: HTMLAppWidgetConfigurationIntent, in context: Context) async -> Timeline<HTMLAppWidgetEntry> {
        var definition = selected(configuration) ?? HTMLAppWidgetStore.preferredDefinition() ?? (HTMLAppSharedContainer.appGroupAvailable ? .placeholder() : .unavailable())
        definition = await HTMLAppWidgetNetwork.refreshed(definition)
        if definition.appID != "placeholder" {
            HTMLAppWidgetStore.save(definition)
        }
        let interval = definition.refresh.map { max(15, $0.intervalMinutes) } ?? 60
        return Timeline(
            entries: [.init(date: Date(), definition: definition)],
            policy: .after(Date().addingTimeInterval(TimeInterval(interval * 60)))
        )
    }

    private func selected(_ configuration: HTMLAppWidgetConfigurationIntent) -> HTMLAppWidgetDefinition? {
        guard let id = configuration.widget?.id else { return nil }
        return HTMLAppWidgetStore.definition(compositeID: id)
    }
}

struct HTMLAppWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HTMLAppWidgetEntry

    private var snapshot: HTMLAppWidgetSnapshot { entry.definition.snapshot }

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                widgetContent
                    .containerBackground(for: .widget) { background }
            } else {
                widgetContent
                    .background(background)
            }
        }
        .widgetURL(deepLink)
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .systemSmall:
            compactCard
        case .systemMedium:
            mediumCard
        case .systemLarge, .systemExtraLarge:
            largeCard
        @unknown default:
            compactCard
        }
    }

    private var inlineView: some View {
        HStack(spacing: 4) {
            if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                Image(systemName: symbol)
            }
            Text([snapshot.title, snapshot.value].compactMap { $0 }.joined(separator: " "))
                .lineLimit(1)
        }
    }

    private var circularView: some View {
        ZStack {
            if let progress = snapshot.progress {
                Gauge(value: min(max(progress, 0), 1)) {
                    EmptyView()
                } currentValueLabel: {
                    circularCenter
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                circularCenter
            }
        }
    }

    @ViewBuilder
    private var circularCenter: some View {
        VStack(spacing: 1) {
            if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                Image(systemName: symbol)
            }
            if let value = snapshot.value, !value.isEmpty {
                Text(value).font(.caption2.bold()).lineLimit(1)
            }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                    Image(systemName: symbol)
                }
                Text(snapshot.title ?? entry.definition.name)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            if let value = snapshot.value, !value.isEmpty {
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
            }
            if let footer = snapshot.footer ?? snapshot.subtitle, !footer.isEmpty {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            heroValue
            if let progress = snapshot.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(accent)
            }
            footer
        }
        .padding(14)
        .foregroundStyle(foreground)
    }

    private var mediumCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Spacer(minLength: 0)
                heroValue
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if snapshot.layout?.lowercased() == "image", let image = decodedImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                itemList(limit: 3)
                    .frame(maxWidth: 140, alignment: .leading)
            }
        }
        .padding(14)
        .foregroundStyle(foreground)
    }

    private var largeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if snapshot.layout?.lowercased() == "image", let image = decodedImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                heroValue
            }
            if let progress = snapshot.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(accent)
            }
            itemList(limit: 6)
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .foregroundStyle(foreground)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let symbol = snapshot.systemSymbol, !symbol.isEmpty {
                Image(systemName: symbol)
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let eyebrow = snapshot.eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .opacity(0.72)
                }
                Text(snapshot.title ?? entry.definition.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var heroValue: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value = snapshot.value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: family == .systemSmall ? 30 : 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
                if let unit = snapshot.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption.bold())
                        .opacity(0.72)
                }
            }
            if let subtitle = snapshot.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.78)
                    .lineLimit(family == .systemSmall ? 2 : 1)
            }
        }
    }

    @ViewBuilder
    private func itemList(limit: Int) -> some View {
        let items = Array((snapshot.items ?? []).prefix(limit))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    HStack(spacing: 7) {
                        if let symbol = item.systemSymbol, !symbol.isEmpty {
                            Image(systemName: symbol)
                                .font(.caption)
                                .foregroundStyle(accent)
                                .frame(width: 15)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.caption2)
                                .opacity(0.72)
                                .lineLimit(1)
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 9))
                                    .opacity(0.55)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(item.value)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let footer = snapshot.footer, !footer.isEmpty {
            Text(footer)
                .font(.caption2)
                .opacity(0.62)
                .lineLimit(1)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(htmlAppHex: snapshot.backgroundHex ?? "#15171B"),
                Color(htmlAppHex: snapshot.backgroundSecondaryHex ?? snapshot.backgroundHex ?? "#15171B")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var foreground: Color {
        Color(htmlAppHex: snapshot.foregroundHex ?? "#FFFFFF")
    }

    private var accent: Color {
        Color(htmlAppHex: snapshot.accentHex ?? "#65A9FF")
    }

    private var decodedImage: Image? {
        guard let encoded = snapshot.imageBase64 else { return nil }
        let raw = encoded.components(separatedBy: ",").last ?? encoded
        guard raw.count <= 1_500_000,
              let data = Data(base64Encoded: raw),
              let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }

    private var deepLink: URL? {
        guard entry.definition.appID != "placeholder" else { return nil }
        var components = URLComponents()
        components.scheme = "htmlapp"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "id", value: entry.definition.appID)]
        return components.url
    }
}

struct HTMLAppPrimaryWidget: Widget {
    let kind = "HTMLAppPrimaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HTMLAppPrimaryWidgetProvider()) { entry in
            HTMLAppWidgetView(entry: entry)
        }
        .configurationDisplayName("HTMLApp Primary")
        .description("Shows the latest primary widget published by a saved HTMLApp.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

@available(iOS 17.0, *)
struct HTMLAppConfiguredWidget: Widget {
    let kind = "HTMLAppGeneratedWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HTMLAppWidgetConfigurationIntent.self,
            provider: HTMLAppConfiguredWidgetProvider()
        ) { entry in
            HTMLAppWidgetView(entry: entry)
        }
        .configurationDisplayName("HTMLApp Widget")
        .description("Choose any widget published by your saved HTMLApps.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

@main
struct HTMLAppWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        HTMLAppPrimaryWidget()
        if #available(iOS 17.0, *) {
            HTMLAppConfiguredWidget()
        }
    }
}

private extension Color {
    init(htmlAppHex raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)

        let red, green, blue, alpha: Double
        switch value.count {
        case 8:
            red = Double((number >> 24) & 0xFF) / 255
            green = Double((number >> 16) & 0xFF) / 255
            blue = Double((number >> 8) & 0xFF) / 255
            alpha = Double(number & 0xFF) / 255
        case 6:
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
            alpha = 1
        default:
            red = 0.08
            green = 0.09
            blue = 0.11
            alpha = 1
        }
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}
