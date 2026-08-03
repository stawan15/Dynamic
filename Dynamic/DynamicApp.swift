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
        MediaController.shared.start()
        OverlayController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemAudioMonitor.shared.stop()
    }
}
