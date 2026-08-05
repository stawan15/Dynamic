import AppKit
import Combine
import SwiftUI
import Sparkle

fileprivate struct VolumeHUDState {
    let level: CGFloat
    let isMuted: Bool
}

@MainActor
final class OverlayController: NSObject, ObservableObject {
    static let shared = OverlayController()
    static let preferredDisplayKey = "preferredDisplayID"
    private var panel: NSPanel?
    @Published fileprivate var expanded = false
    @Published fileprivate var artworkExpanded = false
    @Published fileprivate var volumeHUD: VolumeHUDState?
    private var isVisible = false
    private var hiddenForFullscreen = false
    private var volumeHUDTask: Task<Void, Never>?
    private var fullscreenRecheckTask: Task<Void, Never>?

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        guard UserDefaults.standard.object(forKey: "islandEnabled") as? Bool ?? true else { return }
        if panel == nil { createPanel() }
        guard !anotherAppIsFullscreen else {
            hiddenForFullscreen = true
            scheduleFullscreenRechecks()
            return
        }
        hiddenForFullscreen = false
        positionPanel(animated: false)
        panel?.orderFrontRegardless()
        if (!isVisible || panel?.isVisible == false), let panel {
            panel.alphaValue = 0
            isVisible = true
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.28
                $0.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.85, 0.25, 1.0)
                panel.animator().alphaValue = 1
            }
        } else {
            isVisible = true
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else if let panel, isVisible || panel.isVisible {
            isVisible = false
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0, 0.65, 1)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.completeHide()
                }
            })
        } else {
            isVisible = false
        }
    }

    func playbackChanged(isPlaying: Bool) {
        guard isPlaying else { return }
        show()
    }

    func showVolume(level: CGFloat, isMuted: Bool) {
        volumeHUDTask?.cancel()
        withAnimation(.interpolatingSpring(stiffness: 360, damping: 34)) {
            volumeHUD = VolumeHUDState(level: min(max(level, 0), 1), isMuted: isMuted)
        }
        show()
        positionPanel(animated: true)

        volumeHUDTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self.volumeHUD = nil
            }
            self.positionPanel(animated: true)
        }
    }

    func toggle() {
        guard !artworkExpanded else { return }
        withAnimation(.interpolatingSpring(stiffness: 340, damping: 32)) {
            expanded.toggle()
        }
        positionPanel(animated: true)
    }

    func toggleArtwork() {
        withAnimation(.interpolatingSpring(stiffness: 340, damping: 32)) {
            artworkExpanded.toggle()
            expanded = artworkExpanded
        }
        positionPanel(animated: true)
    }

    func toggleVisibility() {
        let currentlyShown = isVisible && panel?.isVisible == true && (panel?.alphaValue ?? 0) > 0.01
        setVisible(!currentlyShown)
    }

    func lyricChanged() {
        guard expanded || artworkExpanded else { return }
        positionPanel(animated: false)
    }

    func selectDisplay(_ displayID: UInt32?) {
        if let displayID {
            UserDefaults.standard.set(Int(displayID), forKey: Self.preferredDisplayKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.preferredDisplayKey)
        }
        positionPanel(animated: false)
        if isVisible { panel?.orderFrontRegardless() }
    }

    func resetOverlay() {
        UserDefaults.standard.removeObject(forKey: Self.preferredDisplayKey)
        volumeHUDTask?.cancel()
        volumeHUD = nil
        expanded = false
        artworkExpanded = false
        hiddenForFullscreen = false
        show()
    }

    var diagnostics: String {
        let frame = panel?.frame.debugDescription ?? "not created"
        return "Overlay visible: \(isVisible)\nOverlay fullscreen-suppressed: \(hiddenForFullscreen)\nOverlay display: \(selectedScreen?.localizedName ?? "Unavailable")\nOverlay frame: \(frame)"
    }

    private func completeHide() {
        guard !isVisible else { return }
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    @objc private func spaceChanged() {
        updateFullscreenVisibility()
        scheduleFullscreenRechecks()
    }

    @objc private func screenConfigurationChanged() {
        positionPanel(animated: false)
    }

    private func updateFullscreenVisibility() {
        if anotherAppIsFullscreen {
            hiddenForFullscreen = isVisible || hiddenForFullscreen
            setVisible(false)
        } else if hiddenForFullscreen {
            hiddenForFullscreen = false
            show()
        }
    }

    private func scheduleFullscreenRechecks() {
        fullscreenRecheckTask?.cancel()
        fullscreenRecheckTask = Task { [weak self] in
            // Space-change notifications can arrive before the window server finishes its transition.
            for delay in [0.25, 0.5, 1.0, 2.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.updateFullscreenVisibility()
            }
        }
    }

    private var anotherAppIsFullscreen: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let screen = selectedScreen,
              let displayID = displayID(for: screen) else { return false }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        let displayBounds = CGDisplayBounds(displayID)
        return windows.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == app.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            // Maximized windows still leave the menu bar or Dock visible; native fullscreen windows match the display.
            return abs(frame.minX - displayBounds.minX) <= 4 &&
                abs(frame.minY - displayBounds.minY) <= 4 &&
                abs(frame.width - displayBounds.width) <= 4 &&
                abs(frame.height - displayBounds.height) <= 4
        }
    }

    private var selectedScreen: NSScreen? {
        let preferredID = UInt32(UserDefaults.standard.integer(forKey: Self.preferredDisplayKey))
        if preferredID != 0,
           let screen = NSScreen.screens.first(where: { displayID(for: $0) == preferredID }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func createPanel() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: IslandView(controller: self, media: .shared))
        self.panel = panel
    }

    private func positionPanel(animated: Bool) {
        guard let panel, let screen = selectedScreen else { return }
        let size: NSSize
        if volumeHUD != nil { size = NSSize(width: 185, height: 30) }
        else if artworkExpanded { size = NSSize(width: 238, height: estimatedArtworkHeight()) }
        else if expanded { size = NSSize(width: 280, height: estimatedExpandedHeight()) }
        else { size = NSSize(width: 185, height: 30) }
        let frame = screen.frame
        // The compact player stays entirely inside the menu-bar strip.
        let target = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        let update = { panel.setFrame(target, display: true) }
        if animated {
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.42
                $0.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.88, 0.24, 1.0)
                panel.animator().setFrame(target, display: true)
            }
        } else { update() }
    }

    private func estimatedExpandedHeight() -> CGFloat {
        let width: CGFloat = 280 - 24
        let lines = CGFloat(lyricLineCount(font: .systemFont(ofSize: 10, weight: .semibold), width: width))
        return 158 + max(0, lines - 1) * 13
    }

    private func estimatedArtworkHeight() -> CGFloat {
        let width: CGFloat = 238 - 28
        let lines = CGFloat(lyricLineCount(font: .systemFont(ofSize: 11, weight: .semibold), width: width))
        return 286 + max(0, lines - 2) * 14
    }

    private func lyricLineCount(font: NSFont, width: CGFloat) -> Int {
        let text = MediaController.shared.currentLyric
        guard !text.isEmpty else { return 1 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = font.ascender - font.descender + font.leading
        return max(1, Int(ceil(bounds.height / lineHeight)))
    }
}

private struct IslandView: View {
    @ObservedObject var controller: OverlayController
    @ObservedObject var media: MediaController
    @ObservedObject private var systemAudio = SystemAudioMonitor.shared

    var body: some View {
        Group {
            if let volume = controller.volumeHUD {
                VolumeHUDView(state: volume)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else {
                mediaIsland
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(.interpolatingSpring(stiffness: 360, damping: 34), value: controller.volumeHUD != nil)
    }

    @ViewBuilder private var mediaIsland: some View {
        let controlsOpen = controller.expanded
        VStack(spacing: 0) {
            if controller.artworkExpanded {
                VStack(spacing: 10) {
                    Button(action: controller.toggleArtwork) { artwork(size: 190) }
                        .buttonStyle(.plain)
                    Text(media.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(media.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    Text(media.currentLyric.isEmpty ? "Tap the artwork to close" : media.currentLyric)
                        .font(.caption2.weight(media.currentLyric.isEmpty ? .regular : .semibold))
                        .foregroundStyle(.white.opacity(media.currentLyric.isEmpty ? 0.42 : 0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                }
                .padding(14)
            } else {
                HStack(spacing: controlsOpen ? 10 : 7) {
                    Button(action: controller.toggleArtwork) { artwork(size: controlsOpen ? 32 : 21) }
                        .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.title)
                        .font(.system(size: controlsOpen ? 12.5 : 9.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(media.artist)
                        .font(.system(size: controlsOpen ? 10 : 7.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: controlsOpen ? 0 : 1)
                Spacer(minLength: 0)
                if media.hasTrack {
                    PlaybackWaveform(isPlaying: media.isPlaying, level: systemAudio.level, color: media.artworkTint)
                }
            }
            .padding(.horizontal, controlsOpen ? 12 : 7)
            .frame(height: controlsOpen ? 46 : 30)

                if controller.expanded {
                    VStack(spacing: 9) {
                        ProgressView(value: media.duration > 0 ? media.position / media.duration : 0)
                            .tint(.white).padding(.horizontal, 16)
                        HStack(spacing: 32) {
                            Button(action: media.previous) { Image(systemName: "backward.fill") }
                            Button(action: media.togglePlayPause) { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.title3) }
                            Button(action: media.next) { Image(systemName: "forward.fill") }
                        }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        Text(media.source == .none ? "Waiting for music" : media.source.displayName)
                            .font(.caption2).foregroundStyle(.white.opacity(0.5))
                        Text(media.currentLyric.isEmpty ? "Lyrics appear here when available" : media.currentLyric)
                            .font(.system(size: 10, weight: media.currentLyric.isEmpty ? .regular : .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(media.currentLyric.isEmpty ? 0.34 : 0.72))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, 11)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.97), in: RoundedRectangle(cornerRadius: controller.expanded ? 20 : 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: controller.expanded ? 21 : 19, style: .continuous).stroke(.white.opacity(0.30), lineWidth: 0.5) }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { controller.toggle() }
        .onChange(of: media.currentLyric) { controller.lyricChanged() }
        .animation(.interpolatingSpring(stiffness: 340, damping: 32), value: controller.expanded)
        .animation(.interpolatingSpring(stiffness: 340, damping: 32), value: controller.artworkExpanded)
    }

    @ViewBuilder private func artwork(size: CGFloat) -> some View {
        AsyncImage(url: media.artworkURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: media.source == .spotify ? "music.note" : "music.note.list")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: size > 30 ? 13 : 6))
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? 13 : 6))
    }
}

private struct VolumeHUDView: View {
    let state: VolumeHUDState

    private var icon: String {
        if state.isMuted || state.level <= 0.001 { return "speaker.slash.fill" }
        if state.level < 0.34 { return "speaker.wave.1.fill" }
        if state.level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 15)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * (state.isMuted ? 0 : state.level))
                }
            }
            .frame(height: 4)

            Text(state.isMuted ? "MUTE" : "\(Int((state.level * 100).rounded()))%")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 30, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 9)
        .frame(width: 185, height: 30)
        .foregroundStyle(.white)
        .background(.black.opacity(0.97), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.isMuted ? "Muted" : "Volume \(Int((state.level * 100).rounded())) percent")
    }
}

private struct PlaybackWaveform: View {
    let isPlaying: Bool
    let level: CGFloat
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 1.8) {
            ForEach(0..<4, id: \.self) { index in
                let profile: [CGFloat] = [0.58, 1.0, 0.82, 0.48]
                let amplitude = isPlaying ? 3.0 + level * 11.0 * profile[index] : 3.0
                Capsule()
                    .fill(isPlaying ? color : Color.white.opacity(0.45))
                    .frame(width: 2.2, height: amplitude)
            }
        }
        .frame(width: 13, height: 14)
        .scaleEffect(x: 1, y: 1.55, anchor: .center)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var media: MediaController
    let updater: SPUUpdater

    var body: some View {
        Text(media.hasTrack ? "\(media.title) — \(media.artist)" : "No media playing")
        Divider()
        Button(media.isPlaying ? "Pause" : "Play") { media.togglePlayPause() }
        Button("Next Track") { media.next() }
        Button("Show / Hide Island") { OverlayController.shared.toggleVisibility() }
        Divider()
        Button("Settings…") {
            openSettings()
            Task { @MainActor in
                await Task.yield()
                NSApplication.shared.activate()
                NSApplication.shared.windows
                    .first(where: { $0.canBecomeKey && !($0 is NSPanel) })?
                    .makeKeyAndOrderFront(nil)
            }
        }
        CheckForUpdatesView(updater: updater)
        Divider()
        Button("Quit Dynamix") { NSApplication.shared.terminate(nil) }
    }
}

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
