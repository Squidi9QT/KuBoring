import SwiftUI
import CoreAudio
import CoreMediaIO
import KuBoringCore

/// Камера и микрофон «сейчас используются» (любым приложением). Только события, без опроса:
/// камера — CoreMediaIO kCMIODevicePropertyDeviceIsRunningSomewhere, микрофон — то же свойство CoreAudio
/// у устройства ввода по умолчанию.
@MainActor
final class CaptureWatcher {
    private let activities: ActivityCenter
    private var running = false
    private var cameraOn = false
    private var micOn = false

    private var cameraBlock: CMIOObjectPropertyListenerBlock?
    private var cameraDevicesBlock: CMIOObjectPropertyListenerBlock?
    private var watchedCameras: [CMIOObjectID] = []
    private var micBlock: AudioObjectPropertyListenerBlock?
    private var inputDeviceBlock: AudioObjectPropertyListenerBlock?
    private var watchedMic: AudioObjectID = 0

    private static let activityID = "indicators.capture"

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        guard !running else { return }
        running = true
        startCamera()
        startMic()
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        stopCamera()
        stopMic()
        cameraOn = false
        micOn = false
        activities.remove(id: Self.activityID)
    }

    private func refresh() {
        cameraOn = watchedCameras.contains { Self.cmioIsRunning($0) }
        micOn = watchedMic != 0 && Self.audioIsRunning(watchedMic)
        guard cameraOn || micOn else {
            activities.remove(id: Self.activityID)
            return
        }
        let camera = cameraOn, mic = micOn
        activities.post(LiveActivity(
            id: Self.activityID,
            priority: 60,
            extraWidth: 30,
            leading: AnyView(CaptureDot(camera: camera, mic: false)),
            trailing: AnyView(CaptureDot(camera: false, mic: mic))
        ))
    }

    // MARK: Камера (CoreMediaIO)

    private static func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func startCamera() {
        let devicesBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.resubscribeCameras()
                self.refresh()
            }
        }
        var addr = Self.cmioAddress(kCMIOHardwarePropertyDevices)
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, .main, devicesBlock) == noErr {
            cameraDevicesBlock = devicesBlock
        }
        resubscribeCameras()
    }

    private func resubscribeCameras() {
        unsubscribeCameras()
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        cameraBlock = block
        for device in Self.cameraDevices() {
            var addr = Self.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            if CMIOObjectAddPropertyListenerBlock(device, &addr, .main, block) == noErr {
                watchedCameras.append(device)
            }
        }
    }

    private func unsubscribeCameras() {
        if let block = cameraBlock {
            for device in watchedCameras {
                var addr = Self.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
                CMIOObjectRemovePropertyListenerBlock(device, &addr, .main, block)
            }
        }
        watchedCameras = []
        cameraBlock = nil
    }

    private func stopCamera() {
        unsubscribeCameras()
        if let block = cameraDevicesBlock {
            var addr = Self.cmioAddress(kCMIOHardwarePropertyDevices)
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, .main, block)
        }
        cameraDevicesBlock = nil
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var addr = cmioAddress(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func cmioIsRunning(_ device: CMIOObjectID) -> Bool {
        var addr = cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &used, &value) == noErr else { return false }
        return value != 0
    }

    // MARK: Микрофон (CoreAudio)

    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static var runningAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func startMic() {
        let deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.resubscribeMic()
                self.refresh()
            }
        }
        var addr = Self.defaultInputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, deviceBlock) == noErr {
            inputDeviceBlock = deviceBlock
        }
        resubscribeMic()
    }

    private func resubscribeMic() {
        unsubscribeMic()
        var addr = Self.defaultInputAddress
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        var running = Self.runningAddress
        if AudioObjectAddPropertyListenerBlock(device, &running, .main, block) == noErr {
            watchedMic = device
            micBlock = block
        }
    }

    private func unsubscribeMic() {
        if let block = micBlock, watchedMic != 0 {
            var addr = Self.runningAddress
            AudioObjectRemovePropertyListenerBlock(watchedMic, &addr, .main, block)
        }
        watchedMic = 0
        micBlock = nil
    }

    private func stopMic() {
        unsubscribeMic()
        if let block = inputDeviceBlock {
            var addr = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        }
        inputDeviceBlock = nil
    }

    private static func audioIsRunning(_ device: AudioObjectID) -> Bool {
        var addr = runningAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }
}

/// Камера слева (зелёная), микрофон справа (оранжевый) — как индикаторы iPhone.
struct CaptureDot: View {
    let camera: Bool
    let mic: Bool

    var body: some View {
        if camera {
            Image(systemName: "video.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.green)
        } else if mic {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.orange)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
