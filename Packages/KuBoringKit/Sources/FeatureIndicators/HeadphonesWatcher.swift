import SwiftUI
import CoreAudio
import KuBoringCore

/// Заряд Bluetooth-наушников (`system_profiler SPBluetoothDataType -json`).
struct HeadphonesBattery: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Одиночные наушники (Beats, AirPods Max и т.п.).
    var main: Int?

    var symbol: String {
        let n = name.lowercased()
        if n.contains("max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    var hasLevels: Bool { left != nil || right != nil || main != nil }

    /// Разбор JSON system_profiler: подключённые устройства с уровнями заряда.
    static func parse(_ data: Data) -> [HeadphonesBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = bt["device_connected"] as? [[String: Any]] else { return [] }
        var result: [HeadphonesBattery] = []
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                let item = HeadphonesBattery(
                    name: name,
                    left: level(info["device_batteryLevelLeft"]),
                    right: level(info["device_batteryLevelRight"]),
                    caseLevel: level(info["device_batteryLevelCase"]),
                    main: level(info["device_batteryLevelMain"]))
                if item.hasLevels { result.append(item) }
            }
        }
        return result
    }

    /// "75 %" (с неразрывным пробелом) -> 75.
    static func level(_ value: Any?) -> Int? {
        guard let s = value as? String else { return nil }
        let digits = s.filter(\.isNumber)
        guard let n = Int(digits), (0...100).contains(n) else { return nil }
        return n
    }
}

/// Следит за сменой устройства вывода звука: подключились Bluetooth-наушники — показываем их заряд.
/// Без доступа к Bluetooth: событие берём из CoreAudio, заряд — из system_profiler.
@MainActor
final class HeadphonesWatcher {
    private let activities: ActivityCenter
    private var block: AudioObjectPropertyListenerBlock?
    private var lastDevice: AudioObjectID = 0
    private var task: Task<Void, Never>?

    private static let activityID = "indicators.headphones"

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        guard block == nil else { return }
        lastDevice = Self.defaultOutput() ?? 0
        var addr = Self.defaultOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.outputChanged() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block) == noErr {
            self.block = block
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let block {
            var addr = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        }
        block = nil
        activities.remove(id: Self.activityID)
    }

    private func outputChanged() {
        guard let device = Self.defaultOutput(), device != lastDevice else { return }
        lastDevice = device
        guard Self.isBluetooth(device) else { return }
        let deviceName = Self.name(of: device)
        task?.cancel()
        task = Task { [weak self] in
            // Заряд появляется в системе не сразу после подключения — пробуем несколько раз.
            for attempt in 0..<4 {
                try? await Task.sleep(for: .seconds(attempt == 0 ? 1 : 2))
                guard !Task.isCancelled else { return }
                let all = await Self.readBatteries()
                guard !Task.isCancelled else { return }
                let match = all.first { $0.name == deviceName } ?? all.first
                if let match {
                    self?.post(match)
                    return
                }
            }
        }
    }

    private func post(_ battery: HeadphonesBattery) {
        activities.post(LiveActivity(
            id: Self.activityID,
            priority: 90,
            expiresAt: Date().addingTimeInterval(4),
            extraWidth: battery.main != nil ? 52 : 96,
            leading: AnyView(
                Image(systemName: battery.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white)
            ),
            trailing: AnyView(HeadphonesLevelsView(battery: battery))
        ))
    }

    nonisolated private static func readBatteries() async -> [HeadphonesBattery] {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return HeadphonesBattery.parse(data)
        }.value
    }

    // MARK: CoreAudio

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutput() -> AudioObjectID? {
        var addr = defaultOutputAddress
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return (status == noErr && device != 0) ? device : nil
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return "" }
        return value as String
    }
}

/// Уровни справа от выреза: «Л 100 · П 75 · К 8» или один процент.
struct HeadphonesLevelsView: View {
    let battery: HeadphonesBattery

    var body: some View {
        HStack(spacing: 6) {
            if let main = battery.main {
                level(nil, main)
            } else {
                if let l = battery.left { level("Л", l) }
                if let r = battery.right { level("П", r) }
                if let c = battery.caseLevel { level("К", c) }
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .fixedSize()
    }

    private func level(_ label: String?, _ value: Int) -> some View {
        HStack(spacing: 2) {
            if let label {
                Text(label).foregroundStyle(Color.white.opacity(0.5))
            }
            Text("\(value)")
                .foregroundStyle(value <= 15 ? Color.red : Color.white)
        }
    }
}
