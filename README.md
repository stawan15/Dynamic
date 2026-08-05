# Dynamix

<p align="center">
  <img src="Dynamic/Assets.xcassets/DynamixLogo.imageset/Dynamix.svg" width="120" alt="Dynamix logo">
</p>

**Dynamix** is a native macOS menu bar app that turns the area around the MacBook notch into a compact now-playing island. It supports Spotify and Apple Music, system volume feedback, synced lyrics, native media controls, and a desktop widget.

> Dynamix is under active development. APIs and setup requirements may change.

## Features

- Compact floating player positioned in the menu bar
- Expandable playback controls and album artwork
- Spotify and Apple Music metadata and playback control
- Synced lyrics from [LRCLIB](https://lrclib.net)
- System volume and mute HUD
- Audio-reactive waveform using a Core Audio process tap
- Native Now Playing metadata and remote commands through MediaPlayer
- Small, medium, and large macOS desktop widgets
- State restoration after sleep, lock, and user-session changes
- Automatic hiding while another app is fullscreen

## Requirements

- macOS 26.0 or later
- Xcode 26.6 or later
- Spotify or Apple Music
- An Apple Development team for signing the app and widget

## Build

1. Clone the repository:

   ```bash
   git clone https://github.com/stawan15/Dynamic.git
   cd Dynamic
   ```

2. Open `Dynamic.xcodeproj` in Xcode.
3. Select your development team for both the `Dynamic` and `DynamixLockscreenWidget` targets.
4. Replace the app and widget bundle identifiers with identifiers owned by your development team.
5. Configure an App Group for both targets. Forks must replace `group.stawan15.Dynamix` in:

   - `Dynamic/Dynamix.entitlements`
   - `Dynamic/LockscreenWidgetBridge.swift`
   - `DynamixLockscreenWidget/DynamixLockscreenWidget.entitlements`
   - `DynamixLockscreenWidget/DynamixLockscreenWidget.swift`

6. Select the `Dynamix` scheme and run on `My Mac`.

The project can also be compiled from the command line after selecting Xcode as the active developer directory:

```bash
xcodebuild \
  -project Dynamic.xcodeproj \
  -scheme Dynamix \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Permissions

Dynamix requests only the permissions needed by enabled features:

- **Automation:** reads and controls playback in Spotify or Apple Music.
- **System Audio Recording:** powers the audio-reactive waveform. No screen content is captured.

The core player continues to work if System Audio Recording is not granted, but the waveform will not react to playback.

## Releases and Automatic Updates

Release builds use [Sparkle 2](https://sparkle-project.org) for automatic updates. The GitHub Actions release workflow builds a universal app, applies ad-hoc signatures, creates a DMG, generates a cryptographically signed `appcast.xml`, and uploads both files to GitHub Releases. This release process does not require a paid Apple Developer membership.

The workflow only requires this GitHub Actions secret:

| Secret | Value |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key used to sign update archives |

`SPARKLE_PRIVATE_KEY` is already associated with the public key embedded in this project. Keep both the GitHub secret and the `stawan15.Dynamic` keychain item backed up; changing or losing both keys can prevent existing installations from updating.

To publish a release, create and push a semantic version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow sets `MARKETING_VERSION` from the tag and uses the GitHub Actions run number as the monotonically increasing build number. Do not reuse or move a published tag. The first Sparkle-enabled DMG establishes automatic updates; users of that build can then update to later releases from the menu bar or Sparkle's background checks.

Because free releases cannot be signed with an Apple Developer ID or notarized, macOS will warn on the first installation. Drag `Dynamix.app` into Applications, try to open it, then allow it from **System Settings > Privacy & Security > Open Anyway**. If macOS does not show that option, remove the downloaded-file quarantine attribute manually:

```bash
xattr -dr com.apple.quarantine /Applications/Dynamix.app
open /Applications/Dynamix.app
```

Sparkle updates are still protected by the EdDSA key embedded in the app. Gatekeeper will continue to identify the publisher as unknown, and the desktop widget or App Group sharing may be unavailable without Apple-issued distribution signing. The main menu bar app and automatic updates do not require the paid membership.

## Desktop Widget

After running the signed app at least once:

1. Right-click the macOS desktop.
2. Select **Edit Widgets**.
3. Search for **Dynamix Now Playing**.
4. Add the small, medium, or large widget.

The app and widget share the current track, artwork URL, playback position, and lyric timeline through the configured App Group.

## Lyrics

Spotify does not expose its licensed lyrics through AppleScript or its public desktop APIs. Dynamix therefore queries LRCLIB using the current title, artist, album, and duration. Lyrics depend on a matching LRCLIB entry and may not be available for every track or edition.

## Lock Screen Limitations

macOS does not provide a public API for third-party apps to place custom interactive windows over the authentication Lock Screen. Dynamix publishes native Now Playing information where macOS permits and restores the floating island immediately after the user session becomes active.

The large WidgetKit design is a desktop widget with a Lock Screen-inspired appearance. It does not bypass or replace macOS authentication.

## Project Structure

| Path | Purpose |
| --- | --- |
| `Dynamic/MediaController.swift` | Spotify and Apple Music metadata and commands |
| `Dynamic/OverlayController.swift` | Floating island window and SwiftUI interface |
| `Dynamic/SystemAudioMonitor.swift` | Core Audio process tap and waveform level |
| `Dynamic/SystemVolumeMonitor.swift` | System output volume and mute monitoring |
| `Dynamic/LyricsService.swift` | LRCLIB lookup and LRC timestamp parsing |
| `Dynamic/NowPlayingSystemBridge.swift` | Native Now Playing metadata and remote commands |
| `DynamixLockscreenWidget/` | WidgetKit desktop extension |

## Privacy

Dynamix does not include analytics or advertising. Track metadata is sent to LRCLIB for lyric lookup, and artwork is loaded from the URL supplied by the active player. Playback state shared with the widget remains in the local App Group container.

## License

Dynamix is available under the [MIT License](LICENSE).
