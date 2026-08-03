import Foundation
import WidgetKit

enum LockscreenWidgetBridge {
    static let appGroup = "group.stawan15.Dynamix"

    static func publish(
        title: String,
        artist: String,
        source: String,
        artworkURL: URL?,
        isPlaying: Bool,
        position: Double,
        duration: Double
    ) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(title, forKey: "nowPlaying.title")
        defaults.set(artist, forKey: "nowPlaying.artist")
        defaults.set(source, forKey: "nowPlaying.source")
        defaults.set(artworkURL?.absoluteString, forKey: "nowPlaying.artworkURL")
        defaults.set(isPlaying, forKey: "nowPlaying.isPlaying")
        defaults.set(position, forKey: "nowPlaying.position")
        defaults.set(duration, forKey: "nowPlaying.duration")
        defaults.set(Date(), forKey: "nowPlaying.updatedAt")
        WidgetCenter.shared.reloadTimelines(ofKind: "DynamixLockscreenWidget")
    }
}
