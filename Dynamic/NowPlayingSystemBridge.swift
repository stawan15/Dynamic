import AppKit
import MediaPlayer

@MainActor
final class NowPlayingSystemBridge {
    static let shared = NowPlayingSystemBridge()

    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var publishedTrackID = ""
    private var cachedArtworkURL: URL?
    private var cachedArtwork: NSImage?

    private init() {}

    func start() {
        guard commandTargets.isEmpty else { return }
        let commands = MPRemoteCommandCenter.shared()

        register(commands.playCommand) { MediaController.shared.play() }
        register(commands.pauseCommand) { MediaController.shared.pause() }
        register(commands.togglePlayPauseCommand) { MediaController.shared.togglePlayPause() }
        register(commands.nextTrackCommand) { MediaController.shared.next() }
        register(commands.previousTrackCommand) { MediaController.shared.previous() }
    }

    func stop() {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets.removeAll()
        artworkTask?.cancel()
        cachedArtwork = nil
        cachedArtworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func publish(
        title: String,
        artist: String,
        album: String,
        artworkURL: URL?,
        isPlaying: Bool,
        position: Double,
        duration: Double,
        hasTrack: Bool
    ) {
        let center = MPNowPlayingInfoCenter.default()
        guard hasTrack else {
            publishedTrackID = ""
            artworkTask?.cancel()
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            setCommandsEnabled(false)
            return
        }

        let trackID = "\(title)\n\(artist)\n\(album)"
        publishedTrackID = trackID
        var info = baseInfo(
            title: title,
            artist: artist,
            album: album,
            isPlaying: isPlaying,
            position: position,
            duration: duration
        )
        if artworkURL == cachedArtworkURL, let cachedArtwork {
            info[MPMediaItemPropertyArtwork] = mediaArtwork(from: cachedArtwork)
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        setCommandsEnabled(true)

        guard artworkURL != cachedArtworkURL else { return }
        artworkTask?.cancel()
        cachedArtworkURL = artworkURL
        cachedArtwork = nil
        guard let artworkURL else { return }
        artworkTask = Task { [weak self] in
            guard let self,
                  let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  !Task.isCancelled,
                  let image = NSImage(data: data),
                  self.publishedTrackID == trackID else { return }
            self.cachedArtwork = image
            info[MPMediaItemPropertyArtwork] = self.mediaArtwork(from: image)
            center.nowPlayingInfo = info
        }
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
        let target = command.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
        commandTargets.append((command, target))
    }

    private func baseInfo(
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        position: Double,
        duration: Double
    ) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(position, 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if !album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = album }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        return info
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = enabled
        commands.pauseCommand.isEnabled = enabled
        commands.togglePlayPauseCommand.isEnabled = enabled
        commands.nextTrackCommand.isEnabled = enabled
        commands.previousTrackCommand.isEnabled = enabled
    }

    private func mediaArtwork(from image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
