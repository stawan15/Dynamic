import AppKit
import Combine
import Foundation
import SwiftUI

enum PlayerSource: String {
    case spotify = "Spotify"
    case music = "Music"
    case none = "None"

    var displayName: String { rawValue }
}

@MainActor
final class MediaController: ObservableObject {
    static let shared = MediaController()

    @Published private(set) var title = "No media playing"
    @Published private(set) var artist = "Open Spotify or Apple Music"
    @Published private(set) var album = ""
    @Published private(set) var artworkURL: URL?
    @Published private(set) var artworkTint = Color.green
    @Published private(set) var isPlaying = false
    @Published private(set) var source: PlayerSource = .none
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0

    var hasTrack: Bool { source != .none }
    var preferredPlayer: String = UserDefaults.standard.string(forKey: "preferredPlayer") ?? "Automatic"
    private var timer: Timer?
    private var artworkTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(refreshTimerFired(_:)), userInfo: nil, repeats: true)
    }

    @objc private func refreshTimerFired(_ timer: Timer) {
        refresh()
    }

    func refresh() {
        let candidates: [PlayerSource]
        switch preferredPlayer {
        case "Spotify": candidates = [.spotify]
        case "Music": candidates = [.music]
        default: candidates = [.spotify, .music]
        }

        for candidate in candidates {
            if let state = read(source: candidate), state.hasTrack {
                apply(state)
                return
            }
        }
        apply(.empty)
    }

    func togglePlayPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    private func command(_ command: String) {
        guard source != .none else { return }
        let app = source.rawValue
        let script = "tell application \"\(app)\" to \(command)"
        _ = run(script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refresh() }
    }

    private func read(source: PlayerSource) -> PlaybackState? {
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application \"Spotify\"
                if it is running then
                    set t to name of current track
                    set a to artist of current track
                    set al to album of current track
                    set u to artwork url of current track
                    set p to player position
                    set d to duration of current track / 1000
                    set s to (player state as text)
                    return t & linefeed & a & linefeed & al & linefeed & u & linefeed & p & linefeed & d & linefeed & s
                end if
            end tell
            """
        case .music:
            script = """
            tell application \"Music\"
                if it is running and player state is not stopped then
                    set t to name of current track
                    set a to artist of current track
                    set al to album of current track
                    set p to player position
                    set d to duration of current track
                    set s to (player state as text)
                    return t & linefeed & a & linefeed & al & linefeed & linefeed & p & linefeed & d & linefeed & s
                end if
            end tell
            """
        case .none:
            return nil
        }

        guard let output = run(script), !output.isEmpty else { return nil }
        let values = output.components(separatedBy: .newlines)
        guard values.count >= 7 else { return nil }
        return PlaybackState(
            title: values[0], artist: values[1], album: values[2],
            artworkURL: artworkURL(from: values[3]), position: Double(values[4]) ?? 0,
            duration: Double(values[5]) ?? 0, isPlaying: values[6].lowercased().contains("playing"), source: source
        )
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }

    private func artworkURL(from value: String) -> URL? {
        // Spotify's AppleScript API returns `spotify:image:<image-id>`, not a web URL.
        guard !value.isEmpty, value.lowercased() != "missing value" else { return nil }
        if value.hasPrefix("spotify:image:") {
            let imageID = String(value.dropFirst("spotify:image:".count))
            return URL(string: "https://i.scdn.co/image/\(imageID)")
        }
        return URL(string: value)
    }

    private func apply(_ state: PlaybackState) {
        let changed = title != state.title || artist != state.artist || source != state.source || isPlaying != state.isPlaying
        let artworkChanged = artworkURL != state.artworkURL
        title = state.title; artist = state.artist; album = state.album; artworkURL = state.artworkURL
        position = state.position; duration = state.duration; isPlaying = state.isPlaying; source = state.source
        if artworkChanged { updateArtworkTint(from: state.artworkURL) }
        LockscreenWidgetBridge.publish(
            title: state.title,
            artist: state.artist,
            source: state.source.displayName,
            artworkURL: state.artworkURL,
            isPlaying: state.isPlaying,
            position: state.position,
            duration: state.duration
        )
        SystemAudioMonitor.shared.start(for: state.source)
        if changed { OverlayController.shared.playbackChanged(isPlaying: state.isPlaying) }
    }

    private func updateArtworkTint(from url: URL?) {
        artworkTask?.cancel()
        guard let url else { artworkTint = .green; return }
        artworkTask = Task { [weak self] in
            guard let self else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled,
                  let bitmap = NSBitmapImageRep(data: data) else { return }

            let samples = 8
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            for x in 0..<samples {
                for y in 0..<samples {
                    let pixelX = max(0, min(bitmap.pixelsWide - 1, (x * bitmap.pixelsWide) / samples))
                    let pixelY = max(0, min(bitmap.pixelsHigh - 1, (y * bitmap.pixelsHigh) / samples))
                    guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB) else { continue }
                    red += color.redComponent; green += color.greenComponent; blue += color.blueComponent
                }
            }
            let divisor = CGFloat(samples * samples)
            // Lift dark artwork a little so the waveform remains visible on the black Island.
            let color = NSColor(calibratedRed: max(red / divisor, 0.20), green: max(green / divisor, 0.20), blue: max(blue / divisor, 0.20), alpha: 1)
            artworkTint = Color(nsColor: color)
        }
    }
}

private struct PlaybackState {
    let title: String; let artist: String; let album: String; let artworkURL: URL?
    let position: Double; let duration: Double; let isPlaying: Bool; let source: PlayerSource
    var hasTrack: Bool { source != .none && !title.isEmpty }
    static let empty = PlaybackState(title: "No media playing", artist: "Open Spotify or Apple Music", album: "", artworkURL: nil, position: 0, duration: 0, isPlaying: false, source: .none)
}
