import SwiftUI
import Observation
import CoreAudio
import CoreGraphics
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import AppKit
import KuBoringCore

// MARK: - C-колбэк источников питания (глобальная функция, без захвата)

private func powerSourceCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let model = Unmanaged<SystemModel>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in model.powerChanged() }
}

private let virtualMainVolumeSelector: AudioObjectPropertySelector = 0x766D7663

private typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
private typealias BrightnessCallbackFn =
    @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, CFString?, UnsafeRawPointer?, CFDictionary?) -> Void
private typealias BrightnessNotifyFn = @convention(c) (UInt32, UnsafeRawPointer?, BrightnessCallbackFn) -> Int32

private func brightnessChangeCallback(
    _ center: UnsafeRawPointer?, _ observer: UnsafeRawPointer?,
    _ name: CFString?, _ object: UnsafeRawPointer?, _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    let model = Unmanaged<SystemModel>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in model.brightnessEvent() }
}

enum BrightnessMode {
    case event, keys, poll

    var label: String {
        switch self {
        case .event: return "по событию"
        case .keys: return "по клавишам"
        case .poll: return "раз в секунду"
        }
    }
}

private struct PowerInfo {
    var percent: Int
    var onAC: Bool
}

@MainActor @Observable
final class SystemModel {
    let settings: SettingsStore
    private let activities: ActivityCenter

    private(set) var brightnessAvailable = false

    @ObservationIgnored private var volumeRunning = false
    @ObservationIgnored private var deviceBlock: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var volumeBlock: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var watched: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    @ObservationIgnored private var lastVolume: Float = -1
    @ObservationIgnored private var lastMuted = false

    @ObservationIgnored private var dsHandle: UnsafeMutableRawPointer?
    @ObservationIgnored private var brightnessFn: GetBrightnessFn?
    @ObservationIgnored private var brightnessTask: Task<Void, Never>?
    @ObservationIgnored private var registerFn: BrightnessNotifyFn?
    @ObservationIgnored private var unregisterFn: BrightnessNotifyFn?
    @ObservationIgnored private var eventRegistered = false
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var burstUntil = Date.distantPast
    private(set) var brightnessMode: BrightnessMode?
    @ObservationIgnored private var lastBrightness: Float = -1

    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var lastOnAC: Bool?
    @ObservationIgnored private var lowNotified = false

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var assertionActive = false

    init(context: FeatureContext) {
        self.settings = context.settings
        self.activities = context.activities
        resolveBrightness()
    }

    func settingsChanged() {
        if settings[SystemKeys.hudVolume] { startVolume() } else { stopVolume() }
        if settings[SystemKeys.hudBrightness] && brightnessAvailable { startBrightness() } else { stopBrightness() }
        if settings[SystemKeys.battery] { startBattery() } else { stopBattery() }
        applyKeepAwake()
    }

    func shutdown() {
        stopVolume()
        stopBrightness()
        stopBattery()
        releaseAssertion()
        activities.remove(id: "system.hud")
        activities.remove(id: "system.battery")
        activities.remove(id: "system.awake")
        if let dsHandle { dlclose(dsHandle) }
        dsHandle = nil
        brightnessFn = nil
        registerFn = nil
        unregisterFn = nil
    }

    // MARK: HUD

    private func postHUD(symbol: String, level: Float) {
        activities.post(
            LiveActivity(
                id: "system.hud",
                priority: 100,
                expiresAt: Date().addingTimeInterval(1.5),
                extraWidth: 56,
                leading: AnyView(
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                ),
                trailing: AnyView(SystemLevelBar(level: Double(level)))
            ))
    }

    // MARK: Громкость (CoreAudio)

    private func startVolume() {
        guard !volumeRunning else { return }
        volumeRunning = true
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.defaultDeviceChanged() }
        }
        deviceBlock = block
        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        subscribeVolume()
    }

    private func stopVolume() {
        guard volumeRunning else { return }
        volumeRunning = false
        unsubscribeVolume()
        if let block = deviceBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        }
        deviceBlock = nil
    }

    private func defaultDeviceChanged() {
        guard volumeRunning else { return }
        subscribeVolume()
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return (status == noErr && device != 0) ? device : nil
    }

    private func subscribeVolume() {
        unsubscribeVolume()
        guard let device = defaultOutputDevice() else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.volumeChanged() }
        }
        volumeBlock = block
        let scope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        let candidates: [AudioObjectPropertyAddress] = [
            AudioObjectPropertyAddress(
                mSelector: virtualMainVolumeSelector, mScope: scope, mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: 1),
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: 2),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: kAudioObjectPropertyElementMain),
        ]
        for candidate in candidates {
            var addr = candidate
            if AudioObjectHasProperty(device, &addr),
                AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block) == noErr {
                watched.append((device, candidate))
            }
        }
        lastVolume = readVolume(device) ?? -1
        lastMuted = readMute(device)
    }

    private func unsubscribeVolume() {
        if let block = volumeBlock {
            for (device, original) in watched {
                var addr = original
                _ = AudioObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, block)
            }
        }
        watched.removeAll()
        volumeBlock = nil
    }

    private func readFloat(
        _ device: AudioObjectID, selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement
    ) -> Float? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: element)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func readVolume(_ device: AudioObjectID) -> Float? {
        if let v = readFloat(device, selector: virtualMainVolumeSelector, element: kAudioObjectPropertyElementMain) {
            return v
        }
        if let v = readFloat(
            device, selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return v
        }
        let channels = [1, 2].compactMap {
            readFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: AudioObjectPropertyElement($0))
        }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float(channels.count)
    }

    private func readMute(_ device: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func volumeChanged() {
        guard volumeRunning, settings[SystemKeys.hudVolume], let device = defaultOutputDevice() else { return }
        let level = readVolume(device) ?? max(lastVolume, 0)
        let muted = readMute(device)
        if abs(level - lastVolume) < 0.0005 && muted == lastMuted { return }
        lastVolume = level
        lastMuted = muted
        let symbol: String
        if muted || level <= 0.001 {
            symbol = "speaker.slash.fill"
        } else if level < 0.34 {
            symbol = "speaker.wave.1.fill"
        } else if level < 0.67 {
            symbol = "speaker.wave.2.fill"
        } else {
            symbol = "speaker.wave.3.fill"
        }
        postHUD(symbol: symbol, level: muted ? 0 : level)
    }

    // MARK: Яркость (DisplayServices, приватный фреймворк)

    private func resolveBrightness() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else {
            dlclose(handle)
            return
        }
        dsHandle = handle
        if let reg = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications") {
            registerFn = unsafeBitCast(reg, to: BrightnessNotifyFn.self)
        }
        if let unreg = dlsym(handle, "DisplayServicesUnregisterForBrightnessChangeNotifications") {
            unregisterFn = unsafeBitCast(unreg, to: BrightnessNotifyFn.self)
        }
        brightnessFn = unsafeBitCast(sym, to: GetBrightnessFn.self)
        brightnessAvailable = readBrightness() != nil
    }

    private func readBrightness() -> Float? {
        guard let fn = brightnessFn else { return nil }
        var value: Float = 0
        let status = fn(CGMainDisplayID(), &value)
        return status == 0 ? value : nil
    }

    private func startBrightness() {
        guard brightnessMode == nil else { return }
        lastBrightness = readBrightness() ?? -1
        if let reg = registerFn {
            let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
            if reg(CGMainDisplayID(), observer, brightnessChangeCallback) == 0 {
                eventRegistered = true
                brightnessMode = .event
            }
        }
        if brightnessMode == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                guard event.subtype.rawValue == 8 else { return }
                let keyCode = (event.data1 & 0xFFFF0000) >> 16
                guard keyCode == 2 || keyCode == 3 else { return }
                Task { @MainActor in self?.brightnessKeyPressed() }
            }
            brightnessMode = keyMonitor != nil ? .keys : .poll
        }
        restartBrightnessLoop()
    }

    private func stopBrightness() {
        brightnessTask?.cancel()
        brightnessTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if eventRegistered, let unreg = unregisterFn {
            let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
            _ = unreg(CGMainDisplayID(), observer, brightnessChangeCallback)
        }
        eventRegistered = false
        burstUntil = .distantPast
        brightnessMode = nil
    }

    private func restartBrightnessLoop() {
        brightnessTask?.cancel()
        brightnessTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.brightnessInterval()
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                self.pollBrightness()
            }
        }
    }

    private func brightnessInterval() -> Duration {
        switch brightnessMode {
        case .event: return .seconds(10)
        case .keys: return Date() < burstUntil ? .milliseconds(100) : .seconds(2)
        case .poll, nil: return .seconds(1)
        }
    }

    fileprivate func brightnessEvent() {
        guard brightnessMode != nil else { return }
        pollBrightness()
    }

    private func brightnessKeyPressed() {
        guard brightnessMode == .keys else { return }
        burstUntil = Date().addingTimeInterval(2)
        restartBrightnessLoop()
        pollBrightness()
    }

    private func pollBrightness() {
        guard let value = readBrightness() else { return }
        if lastBrightness >= 0, abs(value - lastBrightness) > 0.002 {
            postHUD(symbol: "sun.max.fill", level: value)
        }
        lastBrightness = value
    }

    // MARK: Зарядка (IOKit)

    private func readPower() -> PowerInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as [AnyObject]?
        else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                let current = desc["Current Capacity"] as? Int,
                let maxCap = desc["Max Capacity"] as? Int, maxCap > 0
            else { continue }
            let state = desc["Power Source State"] as? String
            return PowerInfo(percent: min(100, max(0, current * 100 / maxCap)), onAC: state == "AC Power")
        }
        return nil
    }

    private func startBattery() {
        guard powerSource == nil else { return }
        let info = readPower()
        lastOnAC = info?.onAC
        lowNotified = (info.map { !$0.onAC && $0.percent < 20 }) ?? false
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(powerSourceCallback, context)?.takeRetainedValue() else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSource = source
    }

    private func stopBattery() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
        lastOnAC = nil
    }

    func powerChanged() {
        guard powerSource != nil, settings[SystemKeys.battery], let info = readPower() else { return }
        let previous = lastOnAC
        lastOnAC = info.onAC

        if let previous, previous != info.onAC {
            lowNotified = false
            postBattery(info, plugged: info.onAC)
            return
        }
        if settings[SystemKeys.batteryLow], !info.onAC {
            if info.percent < 20 {
                if !lowNotified {
                    lowNotified = true
                    postBattery(info, plugged: false, low: true)
                }
            } else {
                lowNotified = false
            }
        }
    }

    private func postBattery(_ info: PowerInfo, plugged: Bool, low: Bool = false) {
        let symbol: String
        if plugged {
            symbol = "bolt.fill"
        } else if info.percent > 87 {
            symbol = "battery.100"
        } else if info.percent > 62 {
            symbol = "battery.75"
        } else if info.percent > 37 {
            symbol = "battery.50"
        } else if info.percent > 12 {
            symbol = "battery.25"
        } else {
            symbol = "battery.0"
        }
        let tint: Color = low ? .red : (plugged ? .green : .white)
        activities.post(
            LiveActivity(
                id: "system.battery",
                priority: 70,
                expiresAt: Date().addingTimeInterval(3),
                extraWidth: 52,
                leading: AnyView(
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                ),
                trailing: AnyView(
                    Text("\(info.percent)%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                )
            ))
    }

    // MARK: Не спать (IOPMAssertion)

    private func applyKeepAwake() {
        if settings[SystemKeys.keepAwake] {
            if !assertionActive { createAssertion() }
        } else {
            releaseAssertion()
        }
        if assertionActive && settings[SystemKeys.keepAwakeBadge] {
            activities.post(
                LiveActivity(
                    id: "system.awake",
                    priority: 10,
                    expiresAt: nil,
                    extraWidth: 24,
                    leading: AnyView(
                        Image(systemName: "cup.and.saucer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                    ),
                    trailing: AnyView(Color.clear.frame(width: 1, height: 1))
                ))
        } else {
            activities.remove(id: "system.awake")
        }
    }

    private func createAssertion() {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleDisplaySleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "KuBoring: режим «Не спать»" as CFString,
            &id)
        if result == kIOReturnSuccess {
            assertionID = id
            assertionActive = true
        }
    }

    private func releaseAssertion() {
        if assertionActive {
            IOPMAssertionRelease(assertionID)
        }
        assertionActive = false
        assertionID = 0
        activities.remove(id: "system.awake")
    }
}

struct SystemLevelBar: View {
    let level: Double

    var body: some View {
        let clamped = min(1, max(0, level))
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.25))
            Capsule().fill(Color.white).frame(width: 40 * CGFloat(clamped))
        }
        .frame(width: 40, height: 4)
    }
}
