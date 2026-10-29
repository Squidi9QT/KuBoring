import SwiftUI
import AVFoundation
import AppKit
import KuBoringCore

/// NSView, чей слой — AVCaptureVideoPreviewLayer.
final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func apply(session: AVCaptureSession, mirrored: Bool) {
        if previewLayer.session !== session { previewLayer.session = session }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    /// Нужен, чтобы обновить зеркальность, когда у слоя появится connection.
    let running: Bool

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView(frame: .zero)
        view.apply(session: session, mirrored: mirrored)
        return view
    }

    func updateNSView(_ view: CameraPreviewNSView, context: Context) {
        view.apply(session: session, mirrored: mirrored)
    }
}

struct CameraTabView: View {
    let model: CameraModel

    var body: some View {
        GeometryReader { geo in
            let k = AdaptiveMetrics(size: geo.size).scale
            let radius = adaptiveClamp(14 * k, 10, 24)
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(0.4))
                switch model.state {
                case .starting, .running:
                    // Превью заполняет всю область (resizeAspectFill: пропорции сохраняются, лишнее обрезается).
                    CameraPreview(session: model.session,
                                  mirrored: model.settings[CameraKeys.mirror],
                                  running: model.state == .running)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                case .idle:
                    ProgressView().controlSize(.small)
                case .denied:
                    info("Нет доступа к камере. Разрешите его в Системных настройках → Конфиденциальность → Камера.",
                         symbol: "camera.fill", button: "Открыть настройки", k: k) { model.openPrivacySettings() }
                case .noCamera:
                    info("Камера не найдена или занята другим приложением.",
                         symbol: "video.slash", button: nil, k: k) {}
                }
            }
            .padding(adaptiveClamp(8 * k, 6, 14))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { model.viewAppeared() }
        .onDisappear { model.viewDisappeared() }
    }

    private func info(_ text: String, symbol: String, button: String?, k: CGFloat, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8 * k) {
            Image(systemName: symbol).font(.system(size: 24 * k))
            Text(text)
                .font(.system(size: 13 * k))
                .multilineTextAlignment(.center)
            if let button {
                Button(button, action: action)
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(16 * k)
    }
}

struct CameraSettingsView: View {
    let model: CameraModel

    var body: some View {
        Group {
            SettingsSection("Изображение",
                            footer: "Камера включается только пока открыта вкладка «Зеркало» и выключается при её закрытии.") {
                SettingsToggle("Зеркалить изображение",
                               hint: "Показывать картинку как в зеркале (левое и правое меняются местами).",
                               isOn: model.settings.binding(CameraKeys.mirror))
            }
        }
    }
}
