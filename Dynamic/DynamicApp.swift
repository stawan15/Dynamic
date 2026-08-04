import SwiftUI

@main
struct DynamicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var media = MediaController.shared

    var body: some Scene {
        Settings {
            ContentView(media: media)
        }

        MenuBarExtra {
            MenuBarView(media: media)
        } label: {
            Image(nsImage: DynamixIcons.tray)
        }
        .menuBarExtraStyle(.menu)
    }
}

enum DynamixIcons {
    static let tray: NSImage = {
        let image = (NSImage(named: "DynamixLogo")?.copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.didWakeNotification, object: nil)
        NowPlayingSystemBridge.shared.start()
        MediaController.shared.start()
        SystemVolumeMonitor.shared.start()
        OverlayController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        MediaController.shared.persistCurrentState()
        NowPlayingSystemBridge.shared.stop()
        SystemVolumeMonitor.shared.stop()
        SystemAudioMonitor.shared.stop()
    }

    @objc private func sessionResigned() {
        MediaController.shared.persistCurrentState()
        OverlayController.shared.setVisible(false)
    }

    @objc private func sessionActivated() {
        MediaController.shared.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            OverlayController.shared.show()
        }
    }
}
