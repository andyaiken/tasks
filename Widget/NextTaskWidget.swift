import SwiftUI
import TasksCore
import WidgetKit

/// The Next up widget (SPEC §11): the one task to do next — the top of the main list.
struct NextTaskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTaskWidget", provider: Provider()) { entry in
            NextTaskView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("The one thing to do next.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall]
        #endif
    }
}

struct NextTaskView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueEntry

    /// The most urgent task; your own come first once lists are shared (§8).
    private var next: MainListItem? { entry.items.first }

    var body: some View {
        #if os(iOS)
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: small
        }
        #else
        small
        #endif
    }

    @ViewBuilder
    private var small: some View {
        if let next {
            VStack(alignment: .leading, spacing: 6) {
                Text("Next up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Circle()
                    .strokeBorder(next.band.color, lineWidth: 3)
                    .frame(width: 22, height: 22)
                Text(next.chore.title)
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Text(next.band.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(next.band.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            NothingToDoView()
        }
    }

    private var inline: some View {
        Text(next.map { "Next: \($0.chore.title)" } ?? "Nothing to do")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Next up")
                .font(.caption)
                .widgetAccentable()
            Text(next?.chore.title ?? "Nothing to do")
                .font(.headline)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown by either widget when nothing is on the main list.
struct NothingToDoView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
            Text("Nothing needs doing")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
