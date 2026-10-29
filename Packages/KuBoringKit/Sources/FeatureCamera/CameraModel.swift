import SwiftUI
import AppKit
import Observation
import AVFoundation
import KuBoringCore

enum CameraKeys {
    static let mirror = SettingKey<Bool>("feature.camera.mirror", default: true)
}

/// Владелец AVCaptureSession; вся работа с сессией — на собственной очереди, не на main.
final class CameraController: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "kuboring.camera.session")
    private var configured = false

    /// Настроить (при необходимости) и запустить. completion(false) — камера не найдена.
    func start(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard configureIfNeeded() else {
                completion(false)
                return
            }
            if !session.isRunning { session.startRunning() }
            completion(true)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() -> Bool {
        if configured { return true }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        let device = discovery.devices.first(where: { $0.position == .front })
            ?? discovery.devices.first
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.commitConfiguration()
        configured = true
        return true
    }
}

enum CameraState {
    case idle, starting, running, denied, noCamera
}

@MainActor @Observable
final class CameraModel {
    let settings: SettingsStore
    private(set) var state: CameraState = .idle

    @ObservationIgnored private let controller = CameraController()
    @ObservationIgnored private var visible = false

    var session: AVCaptureSession { controller.session }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func viewAppeared() {
        visible = true
        Task { await prepareAndStart() }
    }

    func viewDisappeared() {
        visible = false
        controller.stop()
        if state == .running || state == .starting { state = .idle }
    }

    func shutdown() {
        visible = false
        controller.stop()
        state = .idle
    }

    private func prepareAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        guard visible else { return }
        state = .starting
        controller.start { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                if !self.visible {
                    self.controller.stop()
                    return
                }
                self.state = ok ? .running : .noCamera
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
