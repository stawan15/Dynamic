import AppKit
import Carbon.HIToolbox
import Combine
import CoreServices
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()

    @Published private(set) var isEnabled = false
    @Published private(set) var status = "Disabled"

    private init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            status = "Enabled"
        case .requiresApproval:
            isEnabled = false
            status = "Approval required in Login Items"
        case .notFound:
            isEnabled = false
            status = "Move Dynamix to Applications first"
        default:
            isEnabled = false
            status = "Disabled"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            status = error.localizedDescription
        }
    }
}

struct DisplayOption: Identifiable, Hashable {
    let id: UInt32
    let name: String

    static var available: [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayOption(id: number.uint32Value, name: screen.localizedName)
        }
    }
}

enum AutomationPermission: String {
    case allowed = "Allowed"
    case denied = "Denied"
    case notDetermined = "Not requested"
    case unavailable = "Player not installed"

    static func status(forBundleIdentifier bundleIdentifier: String) -> AutomationPermission {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil else { return .unavailable }
        var target = AEAddressDesc()
        let identifierData = Data(bundleIdentifier.utf8)
        let createStatus = identifierData.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                identifierData.count,
                &target
            )
        }
        guard createStatus == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
        if status == noErr { return .allowed }
        if status == errAEEventNotPermitted { return .denied }
        return .notDetermined
    }
}

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case commandOptionD
    case controlOptionD
    case commandShiftD

    var id: String { rawValue }

    var label: String {
        switch self {
        case .commandOptionD: "⌘⌥D"
        case .controlOptionD: "⌃⌥D"
        case .commandShiftD: "⌘⇧D"
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .commandOptionD: UInt32(cmdKey | optionKey)
        case .controlOptionD: UInt32(controlKey | optionKey)
        case .commandShiftD: UInt32(cmdKey | shiftKey)
        }
    }
}

@MainActor
final class GlobalShortcutManager: ObservableObject {
    static let shared = GlobalShortcutManager()
    static let enabledKey = "globalShortcutsEnabled"
    static let presetKey = "globalShortcutPreset"

    @Published private(set) var status = "Disabled"

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    private init() {}

    func start() {
        guard eventHandler == nil else {
            registerHotKeys()
            return
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return result }
                Task { @MainActor in
                    GlobalShortcutManager.shared.perform(actionID: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
        registerHotKeys()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        registerHotKeys()
    }

    func setPreset(_ preset: ShortcutPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey)
        registerHotKeys()
    }

    func stop() {
        unregisterHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func unregisterHotKeys() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
    }

    private func registerHotKeys() {
        unregisterHotKeys()
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        guard enabled else {
            status = "Disabled"
            return
        }

        let preset = ShortcutPreset(rawValue: defaults.string(forKey: Self.presetKey) ?? "") ?? .commandOptionD
        let definitions: [(UInt32, UInt32, UInt32)] = [
            (1, UInt32(kVK_ANSI_D), preset.modifiers),
            (2, UInt32(kVK_Space), UInt32(controlKey | optionKey)),
            (3, UInt32(kVK_RightArrow), UInt32(controlKey | optionKey)),
            (4, UInt32(kVK_LeftArrow), UInt32(controlKey | optionKey)),
            (5, UInt32(kVK_UpArrow), UInt32(controlKey | optionKey))
        ]
        var failures = 0
        for (id, keyCode, modifiers) in definitions {
            var hotKey: EventHotKeyRef?
            let result = RegisterEventHotKey(
                keyCode,
                modifiers,
                EventHotKeyID(signature: 0x44594E58, id: id),
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            if result == noErr, let hotKey {
                hotKeys.append(hotKey)
            } else {
                failures += 1
            }
        }
        status = failures == 0 ? "5 shortcuts active" : "Shortcut conflict detected"
    }

    private func perform(actionID: UInt32) {
        switch actionID {
        case 1: OverlayController.shared.toggleVisibility()
        case 2: MediaController.shared.togglePlayPause()
        case 3: MediaController.shared.next()
        case 4: MediaController.shared.previous()
        case 5: OverlayController.shared.toggle()
        default: break
        }
    }
}
