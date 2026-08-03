import SwiftUI
import WidgetKit

private let appGroup = "group.stawan15.Dynamix"

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let source: String
    let artworkURL: URL?
    let isPlaying: Bool
    let position: Double
    let duration: Double
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = readEntry()
        // The app explicitly reloads this timeline on each media change. The
        // fallback keeps the progress state fresh without waking the widget often.
        let refresh = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func readEntry() -> NowPlayingEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return NowPlayingEntry(
            date: .now,
            title: defaults?.string(forKey: "nowPlaying.title") ?? "No music playing",
            artist: defaults?.string(forKey: "nowPlaying.artist") ?? "Open Dynamix to begin",
            source: defaults?.string(forKey: "nowPlaying.source") ?? "DYNAMIX",
            artworkURL: defaults?.string(forKey: "nowPlaying.artworkURL").flatMap(URL.init(string:)),
            isPlaying: defaults?.bool(forKey: "nowPlaying.isPlaying") ?? false,
            position: defaults?.double(forKey: "nowPlaying.position") ?? 0,
            duration: defaults?.double(forKey: "nowPlaying.duration") ?? 0
        )
    }
}

struct DynamixLockscreenWidget: Widget {
    let kind = "DynamixLockscreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            DynamixLockscreenWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Dynamix Now Playing")
        .description("Album artwork and playback from Dynamix on your desktop and Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct DynamixLockscreenWidgetView: View {
    let entry: NowPlayingEntry

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: entry.artworkURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(systemName: "waveform").font(.title2).foregroundStyle(.white.opacity(0.84)) }
            }
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(entry.artist)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.60))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(entry.isPlaying ? .green : .secondary).frame(width: 5, height: 5)
                    Text(entry.isPlaying ? "PLAYING" : entry.source.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetURL(URL(string: "dynamix://now-playing"))
    }
}

private extension NowPlayingEntry {
    static let placeholder = NowPlayingEntry(
        date: .now, title: "Your music, in motion", artist: "Dynamix", source: "DYNAMIX",
        artworkURL: nil, isPlaying: true, position: 0, duration: 0
    )
}

@main
struct DynamixLockscreenWidgetBundle: WidgetBundle {
    var body: some Widget { DynamixLockscreenWidget() }
}
