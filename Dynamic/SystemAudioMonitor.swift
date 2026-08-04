import AppKit
import Combine
import CoreAudio

/// Uses a Core Audio process tap. Unlike ScreenCaptureKit, this asks macOS for
/// System Audio Recording permission only — no screen content is captured.
@MainActor
final class SystemAudioMonitor: NSObject, ObservableObject {
    static let shared = SystemAudioMonitor()

    @Published private(set) var level: CGFloat = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var status = "Starting system audio…"

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var capturedBundleID: String?
    private let audioQueue = DispatchQueue(label: "Dynamic.systemAudio", qos: .userInteractive)

    private override init() {}

    func start() {
        start(for: .spotify)
    }

    func reconnect(for source: PlayerSource) {
        stop()
        start(for: source)
    }

    func start(for source: PlayerSource) {
        let bundleID: String
        switch source {
        case .spotify: bundleID = "com.spotify.client"
        case .music: bundleID = "com.apple.Music"
        case .none: return
        }
        if capturedBundleID != bundleID, isCapturing { stop() }
        guard !isCapturing else { return }
        guard #available(macOS 14.2, *) else { status = "Requires macOS 14.2 or newer"; return }

        guard let processID = audioProcessObject(forBundleID: bundleID) else {
            status = "Open \(source.displayName) and play a song first"
            return
        }
        let description = CATapDescription(stereoMixdownOfProcesses: [processID])
        description.name = "Dynamic Audio Meter"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted

        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr else { status = "System Audio permission is required (\(tapStatus))"; return }

        guard let tapFormat = audioTapFormat(for: tapID) else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            status = "Could not read the audio format"
            return
        }

        guard let outputDeviceUID = defaultOutputDeviceUID() else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            status = "Could not find the system output device"
            return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dynamic Audio Meter",
            kAudioAggregateDeviceUIDKey: "stawan15.dynamic.audio-meter.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard aggregateStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            status = "Could not create audio meter (\(aggregateStatus))"
            return
        }

        let levelHandler: @Sendable (CGFloat) -> Void = { [weak self] value in
            DispatchQueue.main.async {
                guard let self else { return }
                let target = min(value * 4.0, 1)
                self.level = target > self.level ? target : self.level * 0.82 + target * 0.18
            }
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, audioQueue) { _, inputData, _, outputData, _ in
            // Different output devices expose a tap as input or output. Use whichever
            // buffer carries the live PCM signal.
            let inputLevel = rmsLevel(from: inputData, format: tapFormat)
            let outputLevel = rmsLevel(from: UnsafePointer(outputData), format: tapFormat)
            levelHandler(max(inputLevel, outputLevel))
        }

        guard status == noErr, let ioProcID, AudioDeviceStart(aggregateDeviceID, ioProcID) == noErr else {
            stop()
            self.status = "Could not start system audio (\(status))"
            return
        }
        isCapturing = true
        capturedBundleID = bundleID
        self.status = "System audio connected"
    }

    func stop() {
        guard #available(macOS 14.2, *) else {
            isCapturing = false
            level = 0
            status = "Requires macOS 14.2 or newer"
            return
        }
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        isCapturing = false
        capturedBundleID = nil
        level = 0
        status = "System audio stopped"
    }
}

private func defaultOutputDeviceUID() -> String? {
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else { return nil }

    var uid: Unmanaged<CFString>?
    size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let result = withUnsafeMutablePointer(to: &uid) { pointer in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
    }
    guard result == noErr, let uid else { return nil }
    return uid.takeUnretainedValue() as String
}

private func audioProcessObject(forBundleID bundleID: String) -> AudioObjectID? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
    var pid = app.processIdentifier
    var objectID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let result = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address,
        UInt32(MemoryLayout<pid_t>.size), &pid, &size, &objectID
    )
    return result == noErr && objectID != AudioObjectID(kAudioObjectUnknown) ? objectID : nil
}

private func audioTapFormat(for tapID: AudioObjectID) -> AudioStreamBasicDescription? {
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else { return nil }
    return format
}

private func rmsLevel(from audioBufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) -> CGFloat {
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
    var sum: Float = 0
    var count = 0
    for buffer in buffers {
        guard let data = buffer.mData else { continue }
        let sampleCount = Int(buffer.mDataByteSize) / max(Int(format.mBitsPerChannel / 8), 1)
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in stride(from: 0, to: sampleCount, by: 4) {
                let sample = min(max(samples[index], -1), 1)
                sum += sample * sample
                count += 1
            }
        } else if format.mBitsPerChannel <= 16 {
            let samples = data.assumingMemoryBound(to: Int16.self)
            for index in stride(from: 0, to: sampleCount, by: 4) {
                let sample = Float(samples[index]) / Float(Int16.max)
                sum += sample * sample
                count += 1
            }
        } else {
            let samples = data.assumingMemoryBound(to: Int32.self)
            for index in stride(from: 0, to: sampleCount, by: 4) {
                let sample = Float(samples[index]) / Float(Int32.max)
                sum += sample * sample
                count += 1
            }
        }
    }
    return count > 0 ? CGFloat(sqrt(sum / Float(count))) : 0
}
