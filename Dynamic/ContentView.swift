import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var media: MediaController
    @ObservedObject private var systemAudio = SystemAudioMonitor.shared
    @AppStorage("islandEnabled") private var islandEnabled = true
    @AppStorage("preferredPlayer") private var preferredPlayer = "Automatic"

    init(media: MediaController) {
        self.media = media
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
                    audioCard
                    setupCard
                }
                .padding(22)
            }
        }
        .frame(width: 500, height: 680)
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
            Circle()
                .fill(media.isPlaying ? media.artworkTint : .white.opacity(0.18))
                .frame(width: 9, height: 9)
                .shadow(color: media.artworkTint.opacity(0.8), radius: media.isPlaying ? 6 : 0)
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
        }
        .signalCard(tint: media.artworkTint)
    }

    private var audioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AUDIO PULSE", systemImage: "waveform")
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Text(systemAudio.isCapturing ? "CONNECTED" : "OFFLINE")
                    .font(.system(size: 9, weight: .bold)).tracking(1)
                    .foregroundStyle(systemAudio.isCapturing ? .green : .orange)
            }
            HStack(spacing: 10) {
                Capsule().fill(media.artworkTint).frame(width: max(6, systemAudio.level * 130), height: 7)
                Text(systemAudio.status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer()
                Button("Reconnect") { systemAudio.reconnect(for: media.source) }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(media.artworkTint)
            }
        }
        .signalCard(tint: media.artworkTint)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("SETUP GUIDE", systemImage: "checklist")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Text("ONE-TIME")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(media.artworkTint)
            }

            setupStep(number: "1", title: "Play music", detail: "Open Spotify or Apple Music and start a track.")
            setupStep(number: "2", title: "Enable Audio Pulse", detail: "Press Reconnect above, then allow System Audio when macOS asks.")
            setupStep(number: "3", title: "Allow playback control", detail: "Approve Automation if macOS asks to control your player.")
            setupStep(number: "4", title: "Add the Lock Screen widget", detail: "Right-click the desktop → Edit Widgets → Dynamix → Now Playing.")

            HStack(spacing: 10) {
                Button("Open Privacy Settings") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .tint(media.artworkTint)

                Spacer()

                Text("Dynamix stays hidden in fullscreen.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .signalCard(tint: media.artworkTint)
    }

    private func setupStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(media.artworkTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
            }
        }
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
    ContentView(media: .shared)
}
