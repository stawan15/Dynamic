import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController: NSObject, ObservableObject {
    static let shared = OverlayController()
    private var panel: NSPanel?
    @Published fileprivate var expanded = false
    @Published fileprivate var artworkExpanded = false
    private var isVisible = false

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    func show() {
        guard UserDefaults.standard.object(forKey: "islandEnabled") as? Bool ?? true else { return }
        if panel == nil { createPanel() }
        guard !anotherAppIsFullscreen else { return }
        positionPanel(animated: false)
        panel?.orderFrontRegardless()
        if !isVisible, let panel {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.28
                $0.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.85, 0.25, 1.0)
                panel.animator().alphaValue = 1
            }
        }
        isVisible = true
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else if let panel, isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0, 0.65, 1)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                panel.alphaValue = 1
            })
            isVisible = false
        }
    }

    func playbackChanged(isPlaying: Bool) {
        guard isPlaying else { return }
        show()
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
        setVisible(!isVisible)
    }

    @objc private func spaceChanged() {
        if anotherAppIsFullscreen {
            panel?.orderOut(nil)
            isVisible = false
        } else if UserDefaults.standard.object(forKey: "islandEnabled") as? Bool ?? true {
            show()
        }
    }

    private var anotherAppIsFullscreen: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let screen = NSScreen.main else { return false }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        let screenFrame = screen.frame
        return windows.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == app.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            return frame.width >= screenFrame.width * 0.98 && frame.height >= screenFrame.height * 0.96
        }
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
        guard let panel, let screen = NSScreen.main else { return }
        let size: NSSize
        if artworkExpanded { size = NSSize(width: 238, height: 286) }
        else if expanded { size = NSSize(width: 280, height: 128) }
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
}

private struct IslandView: View {
    @ObservedObject var controller: OverlayController
    @ObservedObject var media: MediaController
    @ObservedObject private var systemAudio = SystemAudioMonitor.shared

    var body: some View {
        let controlsOpen = controller.expanded
        VStack(spacing: 0) {
            if controller.artworkExpanded {
                VStack(spacing: 10) {
                    Button(action: controller.toggleArtwork) { artwork(size: 190) }
                        .buttonStyle(.plain)
                    Text(media.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(media.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    Text("Tap the artwork to close").font(.caption2).foregroundStyle(.white.opacity(0.42))
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
    @ObservedObject var media: MediaController
    var body: some View {
        Text(media.hasTrack ? "\(media.title) — \(media.artist)" : "No media playing")
        Divider()
        Button(media.isPlaying ? "Pause" : "Play") { media.togglePlayPause() }
        Button("Next Track") { media.next() }
        Button("Show / Hide Island") { OverlayController.shared.toggleVisibility() }
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit Dynamix") { NSApplication.shared.terminate(nil) }
    }
}
