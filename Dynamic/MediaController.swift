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
    @Published private(set) var currentLyric = ""
    @Published private(set) var lastAutomationError = "None"

    var hasTrack: Bool { source != .none }
    var preferredPlayer: String = UserDefaults.standard.string(forKey: "preferredPlayer") ?? "Automatic"
    private var timer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var lyrics: [TimedLyric] = []
    private var lyricsTrackID = ""
    private var consecutiveRefreshMisses = 0
    private var scriptCache: [String: NSAppleScript] = [:]

    private init() {
        guard let defaults = UserDefaults(suiteName: LockscreenWidgetBridge.appGroup) else { return }
        title = defaults.string(forKey: "nowPlaying.title") ?? title
        artist = defaults.string(forKey: "nowPlaying.artist") ?? artist
        album = defaults.string(forKey: "nowPlaying.album") ?? album
        artworkURL = defaults.string(forKey: "nowPlaying.artworkURL").flatMap(URL.init(string:))
        isPlaying = defaults.bool(forKey: "nowPlaying.isPlaying")
        position = defaults.double(forKey: "nowPlaying.position")
        duration = defaults.double(forKey: "nowPlaying.duration")
        currentLyric = defaults.string(forKey: "nowPlaying.lyric") ?? ""
        if let storedSource = defaults.string(forKey: "nowPlaying.source"),
           let restoredSource = PlayerSource(rawValue: storedSource) {
            source = restoredSource
        }
    }

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
                consecutiveRefreshMisses = 0
                apply(state)
                return
            }
        }
        consecutiveRefreshMisses += 1
        if consecutiveRefreshMisses >= 3 { apply(.empty) }
    }

    func togglePlayPause() { command("playpause") }
    func play() { command("play") }
    func pause() { command("pause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func persistCurrentState() {
        publishCurrentState()
    }

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
        guard values.count >= 7,
              let position = Double(values[4]),
              let duration = Double(values[5]) else { return nil }
        return PlaybackState(
            title: values[0], artist: values[1], album: values[2],
            artworkURL: artworkURL(from: values[3]), position: position,
            duration: duration, isPlaying: values[6].lowercased().contains("playing"), source: source
        )
    }

    private func run(_ source: String) -> String? {
        let script: NSAppleScript
        if let cached = scriptCache[source] {
            script = cached
        } else if let compiled = NSAppleScript(source: source) {
            scriptCache[source] = compiled
            script = compiled
        } else {
            return nil
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error).stringValue
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            lastAutomationError = "\(number): \(message)"
        }
        return result
    }

    var diagnostics: String {
        "Player: \(source.displayName)\nTrack available: \(hasTrack)\nPlaying: \(isPlaying)\nTrack: \(title) — \(artist)\nLast Automation error: \(lastAutomationError)"
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
        let trackChanged = title != state.title || artist != state.artist || album != state.album || source != state.source
        let changed = title != state.title || artist != state.artist || source != state.source || isPlaying != state.isPlaying
        let artworkChanged = artworkURL != state.artworkURL
        title = state.title; artist = state.artist; album = state.album; artworkURL = state.artworkURL
        position = state.position; duration = state.duration; isPlaying = state.isPlaying; source = state.source
        if artworkChanged { updateArtworkTint(from: state.artworkURL) }
        if trackChanged {
            loadLyrics()
        } else {
            updateCurrentLyric()
        }
        publishCurrentState()
        SystemAudioMonitor.shared.start(for: state.source)
        if changed { OverlayController.shared.playbackChanged(isPlaying: state.isPlaying) }
    }

    private func publishCurrentState() {
        LockscreenWidgetBridge.publish(
            title: title,
            artist: artist,
            album: album,
            source: source.rawValue,
            artworkURL: artworkURL,
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            lyric: currentLyric,
            lyrics: lyrics
        )
        NowPlayingSystemBridge.shared.publish(
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            hasTrack: hasTrack
        )
    }

    private func loadLyrics() {
        lyricsTask?.cancel()
        lyrics = []
        currentLyric = ""
        guard hasTrack else {
            lyricsTrackID = ""
            return
        }

        let trackID = "\(source.rawValue)\n\(title)\n\(artist)\n\(album)"
        lyricsTrackID = trackID
        let title = title
        let artist = artist
        let album = album
        let duration = duration
        lyricsTask = Task { [weak self] in
            let result = await LyricsService.fetch(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
            guard !Task.isCancelled, let self, self.lyricsTrackID == trackID else { return }
            self.lyrics = result
            self.updateCurrentLyric()
            self.publishCurrentState()
        }
    }

    private func updateCurrentLyric() {
        let nextLine = lyrics.last { $0.time <= position + 0.15 }?.text ?? ""
        if currentLyric != nextLine { currentLyric = nextLine }
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
