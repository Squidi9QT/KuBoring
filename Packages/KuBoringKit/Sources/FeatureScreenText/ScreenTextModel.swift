import AppKit
import Vision
import Observation
import KuBoringCore

/// Заготовка под будущую локальную ИИ.
public protocol LocalAIProvider {
    func ask(_ prompt: String) async throws -> String
}

enum ScreenTextKeys {
    static let copyImmediately = SettingKey<Bool>("feature.screentext.copyImmediately", default: true)
}

enum ScreenTextError: LocalizedError {
    case noImage
    var errorDescription: String? { "Не удалось получить изображение из буфера." }
}

/// Распознавание текста (Vision). Не привязано к главному потоку.
enum TextRecognizer {
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}

/// Выделить область экрана -> распознать -> показать/скопировать.
@MainActor @Observable
final class ScreenTextModel {
    enum Status: Equatable {
        case idle, selecting, recognizing
        case failed(String)
    }

    var status: Status = .idle
    var text = ""
    var justCopied = false
    var nothingFound = false

    private(set) var settings: SettingsStore?
    @ObservationIgnored private var notch: NotchController?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    static let holdReason = "screentext.capture"

    func attach(_ context: FeatureContext) {
        settings = context.settings
        notch = context.notch
    }

    func shutdown() {
        job?.cancel()
        job = nil
        flashTask?.cancel()
        flashTask = nil
        notch?.hold(Self.holdReason, false)
        status = .idle
    }

    var isBusy: Bool { status == .selecting || status == .recognizing }

    func capture() {
        guard !isBusy else { return }
        job = Task { [weak self] in
            await self?.runCapture()
        }
    }

    private func runCapture() async {
        status = .selecting
        nothingFound = false
        // Пока выделяем область, шторка не должна закрыться.
        notch?.hold(Self.holdReason, true)
        defer { notch?.hold(Self.holdReason, false) }

        let pb = NSPasteboard.general
        let before = pb.changeCount
        do {
            try await Self.runScreencapture()
        } catch {
            status = .failed("Не удалось запустить выбор области: \(error.localizedDescription)")
            return
        }
        if Task.isCancelled { status = .idle; return }

        // Esc при выделении: буфер не изменился.
        guard pb.changeCount != before else {
            status = .idle
            return
        }
        guard let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            status = .failed(ScreenTextError.noImage.localizedDescription)
            return
        }

        status = .recognizing
        do {
            let recognized = try await Task.detached(priority: .userInitiated) {
                try TextRecognizer.recognize(cg)
            }.value
            if Task.isCancelled { status = .idle; return }
            text = recognized
            nothingFound = recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            status = .idle
            if !nothingFound, settings?[ScreenTextKeys.copyImmediately] ?? true {
                copyText()
            }
        } catch {
            status = .failed("Не удалось распознать текст: \(error.localizedDescription)")
        }
    }

    func copyText() {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        justCopied = true
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.justCopied = false
        }
    }

    /// Интерактивное выделение области экрана в буфер обмена.
    private static func runScreencapture() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c"]
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
