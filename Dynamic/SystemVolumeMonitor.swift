import CoreAudio
import Foundation

@MainActor
final class SystemVolumeMonitor: NSObject {
    static let shared = SystemVolumeMonitor()

    private var timer: Timer?
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var volume: CGFloat?
    private var isMuted: Bool?

    private override init() {}

    func start() {
        guard timer == nil else { return }
        refresh(showHUD: false)
        let timer = Timer(timeInterval: 0.12, target: self, selector: #selector(timerFired(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired(_ timer: Timer) {
        refresh(showHUD: true)
    }

    private func refresh(showHUD: Bool) {
        guard let currentDevice = defaultOutputDevice() else { return }
        let deviceChanged = currentDevice != deviceID
        deviceID = currentDevice

        guard let currentVolume = outputVolume(for: currentDevice) else { return }
        let currentMuted = outputMuted(for: currentDevice) ?? (currentVolume <= 0.001)
        let volumeChanged = volume.map { abs($0 - currentVolume) > 0.001 } ?? false
        let muteChanged = isMuted.map { $0 != currentMuted } ?? false
        let changed = !deviceChanged && (volumeChanged || muteChanged)

        volume = currentVolume
        isMuted = currentMuted
        if showHUD, changed {
            OverlayController.shared.showVolume(level: currentVolume, isMuted: currentMuted)
        }
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var outputDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &outputDevice
        ) == noErr, outputDevice != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return outputDevice
    }

    private func outputVolume(for device: AudioObjectID) -> CGFloat? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if let volume: Float32 = propertyValue(device: device, address: &address) {
            return CGFloat(volume)
        }

        let channelVolumes: [CGFloat] = (1...2).compactMap { channel in
            address.mElement = AudioObjectPropertyElement(channel)
            guard let volume: Float32 = propertyValue(device: device, address: &address) else { return nil }
            return CGFloat(volume)
        }
        guard !channelVolumes.isEmpty else { return nil }
        return channelVolumes.reduce(0, +) / CGFloat(channelVolumes.count)
    }

    private func outputMuted(for device: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard let muted: UInt32 = propertyValue(device: device, address: &address) else { return nil }
        return muted != 0
    }

    private func propertyValue<T>(device: AudioObjectID, address: inout AudioObjectPropertyAddress) -> T? {
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let rawValue = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer { rawValue.deallocate() }
        rawValue.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<T>.size)
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, rawValue) == noErr else { return nil }
        return rawValue.load(as: T.self)
    }
}
