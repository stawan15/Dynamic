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
    let lyric: String
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let now = Date.now
        let entry = readEntry(date: now)
        var entries = [entry]

        if entry.isPlaying, let defaults = UserDefaults(suiteName: appGroup) {
            let updatedAt = defaults.object(forKey: "nowPlaying.updatedAt") as? Date ?? now
            let currentPosition = entry.position + max(0, now.timeIntervalSince(updatedAt))
            let lyrics = defaults.data(forKey: "nowPlaying.lyrics")
                .flatMap { try? JSONDecoder().decode([WidgetTimedLyric].self, from: $0) } ?? []
            for line in lyrics where line.time > currentPosition && line.time <= currentPosition + 300 {
                let date = now.addingTimeInterval(line.time - currentPosition)
                entries.append(entry.updating(date: date, position: line.time, lyric: line.text))
            }
        }

        let refresh = now.addingTimeInterval(300)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func readEntry(date: Date = .now) -> NowPlayingEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return NowPlayingEntry(
            date: date,
            title: defaults?.string(forKey: "nowPlaying.title") ?? "No music playing",
            artist: defaults?.string(forKey: "nowPlaying.artist") ?? "Open Dynamix to begin",
            source: defaults?.string(forKey: "nowPlaying.source") ?? "DYNAMIX",
            artworkURL: defaults?.string(forKey: "nowPlaying.artworkURL").flatMap(URL.init(string:)),
            isPlaying: defaults?.bool(forKey: "nowPlaying.isPlaying") ?? false,
            position: defaults?.double(forKey: "nowPlaying.position") ?? 0,
            duration: defaults?.double(forKey: "nowPlaying.duration") ?? 0,
            lyric: defaults?.string(forKey: "nowPlaying.lyric") ?? ""
        )
    }
}

private struct WidgetTimedLyric: Decodable {
    let time: Double
    let text: String
}

struct DynamixLockscreenWidget: Widget {
    let kind = "DynamixLockscreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            DynamixLockscreenWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Dynamix Now Playing")
        .description("Album artwork and playback from Dynamix on your Mac desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct DynamixLockscreenWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                compactView
            case .systemLarge:
                lockscreenStyleView
            default:
                mediumView
            }
        }
        .widgetURL(URL(string: "dynamix://now-playing"))
    }

    private var mediumView: some View {
        HStack(spacing: 10) {
            artwork(size: 48, radius: 13)

            VStack(alignment: .leading, spacing: 4) {
                trackDetails
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 9) {
            artwork(size: 68, radius: 17)
            trackDetails
            progress
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private var lockscreenStyleView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(entry.date, style: .time)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(entry.source.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            }

            artwork(size: 132, radius: 24)

            VStack(spacing: 5) {
                Text(entry.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(entry.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            progress
                .padding(.horizontal, 20)

            if !entry.lyric.isEmpty {
                Text(entry.lyric)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(2)
                    .frame(minHeight: 32)
                    .padding(.horizontal, 18)
            }

            HStack(spacing: 24) {
                Image(systemName: "backward.fill")
                Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                Image(systemName: "forward.fill")
            }
            .foregroundStyle(.primary.opacity(0.86))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(18)
    }

    private var trackDetails: some View {
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
    }

    private var progress: some View {
        ProgressView(value: entry.duration > 0 ? min(max(entry.position / entry.duration, 0), 1) : 0)
            .progressViewStyle(.linear)
            .tint(.primary.opacity(0.82))
    }

    @ViewBuilder private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        AsyncImage(url: entry.artworkURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .font(size > 80 ? .system(size: 38) : .title2)
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private extension NowPlayingEntry {
    func updating(date: Date, position: Double, lyric: String) -> NowPlayingEntry {
        NowPlayingEntry(
            date: date,
            title: title,
            artist: artist,
            source: source,
            artworkURL: artworkURL,
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            lyric: lyric
        )
    }

    static let placeholder = NowPlayingEntry(
        date: .now, title: "Your music, in motion", artist: "Dynamix", source: "DYNAMIX",
        artworkURL: nil, isPlaying: true, position: 0, duration: 0,
        lyric: "Lyrics move with your music"
    )
}

@main
struct DynamixLockscreenWidgetBundle: WidgetBundle {
    var body: some Widget { DynamixLockscreenWidget() }
}
