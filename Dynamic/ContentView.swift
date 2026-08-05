import AppKit
import Sparkle
import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var media: MediaController
    @ObservedObject private var systemAudio = SystemAudioMonitor.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginController.shared
    @ObservedObject private var shortcuts = GlobalShortcutManager.shared
    @AppStorage("islandEnabled") private var islandEnabled = true
    @AppStorage("preferredPlayer") private var preferredPlayer = "Automatic"
    @AppStorage(GlobalShortcutManager.enabledKey) private var shortcutsEnabled = true
    @AppStorage(GlobalShortcutManager.presetKey) private var shortcutPreset = ShortcutPreset.commandOptionD.rawValue

    private let updater: SPUUpdater

    init(media: MediaController, updater: SPUUpdater) {
        self.media = media
        self.updater = updater
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [media.artworkTint.opacity(0.20), .clear], startPoint: .topTrailing, endPoint: .center)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    nowPlayingCard
                    islandCard
                    startupCard
                    updateCard
                    shortcutCard
                    displayCard
                    permissionCard
                    diagnosticsCard
                }
                .padding(22)
            }
        }
        .frame(width: 500, height: 720)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.055, green: 0.31, blue: 0.30),
                            Color(red: 0.012, green: 0.095, blue: 0.105)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 0.8)
                    }
                Image("DynamixLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .shadow(color: Color(red: 0.86, green: 0.88, blue: 0.55).opacity(0.75), radius: 7)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("DYNAMIX")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(1.8)
                Text("YOUR MUSIC, IN MOTION")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("v\(appVersion)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Circle()
                    .fill(media.isPlaying ? media.artworkTint : .white.opacity(0.18))
                    .frame(width: 9, height: 9)
                    .shadow(color: media.artworkTint.opacity(0.8), radius: media.isPlaying ? 6 : 0)
            }
        }
    }

    private var nowPlayingCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label("NOW PLAYING", systemImage: "music.note")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Text(media.isPlaying ? "LIVE" : "IDLE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(media.isPlaying ? media.artworkTint : .white.opacity(0.4))
            }

            HStack(spacing: 14) {
                AsyncImage(url: media.artworkURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "music.note").font(.title2).foregroundStyle(.white.opacity(0.55)) }
                }
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(media.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(media.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                    Text(media.source.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(media.artworkTint)
                }
                Spacer()
                Button(action: media.togglePlayPause) {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(media.artworkTint, in: Circle())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }

            GeometryReader { proxy in
                let progress = media.duration > 0 ? media.position / media.duration : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(media.artworkTint).frame(width: max(4, proxy.size.width * progress))
                }
            }
            .frame(height: 4)
        }
        .signalCard(tint: media.artworkTint)
    }

    private var islandCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("ISLAND", systemImage: "capsule.fill")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Floating player").font(.system(size: 14, weight: .semibold))
                    Text("Sits in the menu bar until fullscreen").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Toggle("", isOn: $islandEnabled)
                    .labelsHidden()
                    .tint(media.artworkTint)
                    .onChange(of: islandEnabled) { _, enabled in OverlayController.shared.setVisible(enabled) }
            }

            HStack(spacing: 7) {
                ForEach(["Automatic", "Spotify", "Music"], id: \.self) { player in
                    Button {
                        preferredPlayer = player
                        media.preferredPlayer = player
                        media.refresh()
                    } label: {
                        Text(player == "Music" ? "Apple Music" : player)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(preferredPlayer == player ? .black : .white.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(preferredPlayer == player ? media.artworkTint : .white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Reset Position") { OverlayController.shared.resetOverlay() }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(media.artworkTint)
                Spacer()
                Text("Moves the island back to default spot")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .signalCard(tint: media.artworkTint)
    }

    private var startupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("STARTUP", systemImage: "power")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at login").font(.system(size: 14, weight: .semibold))
                    Text("Start Dynamix automatically when you sign in").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .labelsHidden()
                .tint(media.artworkTint)
            }

            Text(launchAtLogin.status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .signalCard(tint: media.artworkTint)
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("UPDATES", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))
            .font(.system(size: 13, weight: .medium))
            .tint(media.artworkTint)

            Toggle("Download updates automatically", isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.automaticallyDownloadsUpdates = $0 }
            ))
            .font(.system(size: 13, weight: .medium))
            .tint(media.artworkTint)
            .disabled(!updater.automaticallyChecksForUpdates)

            HStack {
                Text("Check interval").font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { intervalTag(for: updater.updateCheckInterval) },
                    set: { updater.updateCheckInterval = interval(for: $0) }
                )) {
                    Text("Every 6 hours").tag(21600)
                    Text("Hourly").tag(3600)
                    Text("Daily").tag(86400)
                    Text("Weekly").tag(604800)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!updater.automaticallyChecksForUpdates)
            }

            HStack {
                Text("Last check: \(lastCheckText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button("Check Now…", action: updater.checkForUpdates)
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.bordered)
                    .tint(media.artworkTint)
            }
        }
        .signalCard(tint: media.artworkTint)
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("GLOBAL SHORTCUTS", systemImage: "command")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Media hotkeys").font(.system(size: 14, weight: .semibold))
                    Text("Toggle island & control playback anywhere").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Toggle("", isOn: $shortcutsEnabled)
                    .labelsHidden()
                    .tint(media.artworkTint)
                    .onChange(of: shortcutsEnabled) { _, enabled in
                        shortcuts.setEnabled(enabled)
                    }
            }

            HStack {
                Text("Toggle island").font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { ShortcutPreset(rawValue: shortcutPreset) ?? .commandOptionD },
                    set: { preset in
                        shortcutPreset = preset.rawValue
                        shortcuts.setPreset(preset)
                    }
                )) {
                    ForEach(ShortcutPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .disabled(!shortcutsEnabled)
            }

            HStack(spacing: 6) {
                Text("⌃⌥Space")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
                Text("play/pause").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("⌃⌥←/→")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
                Text("prev/next").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }

            HStack(spacing: 6) {
                Text("⌃⌥↑")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
                Text("expand/collapse island").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Spacer()
            }

            Text(shortcuts.status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .signalCard(tint: media.artworkTint)
    }

    private var displayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("DISPLAY", systemImage: "display")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            HStack {
                Text("Show island on").font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { UserDefaults.standard.integer(forKey: OverlayController.preferredDisplayKey) },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: OverlayController.preferredDisplayKey)
                        OverlayController.shared.selectDisplay(UInt32(newValue))
                    }
                )) {
                    Text("Automatic (main)").tag(0)
                    ForEach(DisplayOption.available) { display in
                        Text(display.name).tag(Int(display.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        }
        .signalCard(tint: media.artworkTint)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("PERMISSIONS", systemImage: "lock.shield")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            permissionRow(
                name: "Spotify control",
                permission: AutomationPermission.status(forBundleIdentifier: "com.spotify.client")
            )
            permissionRow(
                name: "Apple Music control",
                permission: AutomationPermission.status(forBundleIdentifier: "com.apple.Music")
            )
            permissionRow(
                name: "System audio",
                permission: systemAudio.isCapturing ? .allowed : systemAudio.status.contains("not") ? .denied : .notDetermined
            )

            Button("Open Privacy Settings") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
                NSWorkspace.shared.open(url)
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
            .tint(media.artworkTint)
        }
        .signalCard(tint: media.artworkTint)
    }

    private func permissionRow(name: String, permission: AutomationPermission) -> some View {
        HStack {
            Text(name).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(permission.rawValue)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(permission == .allowed ? .green : permission == .denied ? .red : .orange)
        }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("DIAGNOSTICS", systemImage: "stethoscope")
                .font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            Text(diagnosticsText)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button("Export Log") { exportDiagnostics() }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(media.artworkTint)
                Text("Writes a diagnostic report you can share")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .signalCard(tint: media.artworkTint)
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private var lastCheckText: String {
        guard let date = updater.lastUpdateCheckDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func intervalTag(for seconds: TimeInterval) -> Int {
        switch seconds {
        case ..<10800: return 3600
        case 10800..<43200: return 21600
        case 43200..<259200: return 86400
        default: return 604800
        }
    }

    private func interval(for tag: Int) -> TimeInterval {
        TimeInterval(tag)
    }

    private var diagnosticsText: String {
        [
            media.diagnostics,
            OverlayController.shared.diagnostics,
            systemAudio.diagnostics,
            SystemVolumeMonitor.shared.diagnostics,
            "Launch at login: \(launchAtLogin.status)",
            "Shortcuts: \(shortcuts.status)"
        ].joined(separator: "\n")
    }

    private func exportDiagnostics() {
        let body = [
            "Dynamix Diagnostic Report",
            "Version: \(appVersion)",
            "Date: \(ISO8601DateFormatter().string(from: Date()))",
            "========================",
            diagnosticsText
        ].joined(separator: "\n")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dynamix-Diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
        try? body.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private extension View {
    func signalCard(tint: Color) -> some View {
        self
            .padding(16)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(0.23), lineWidth: 0.7) }
    }
}

#Preview {
    ContentView(media: .shared, updater: SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    ).updater)
}
