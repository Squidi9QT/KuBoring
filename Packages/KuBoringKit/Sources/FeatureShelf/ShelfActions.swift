import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Быстрые действия с файлами полки. Результат кладётся рядом с исходным файлом
/// (или в «Загрузки», если туда писать нельзя); исходники не меняются (кроме переименования).
enum ShelfActions {
    enum Failure: LocalizedError {
        case notImage, cannotRead, cannotWrite, zipFailed, nameTaken, badName

        var errorDescription: String? {
            switch self {
            case .notImage: return "Это не картинка"
            case .cannotRead: return "Не удалось прочитать файл"
            case .cannotWrite: return "Не удалось сохранить результат"
            case .zipFailed: return "Не удалось создать архив"
            case .nameTaken: return "Файл с таким именем уже есть"
            case .badName: return "Недопустимое имя"
            }
        }
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Сжать: не больше 2560 px по длинной стороне, JPEG 70%.
    static func compress(_ url: URL) throws -> URL {
        guard isImage(url) else { throw Failure.notImage }
        let out = uniqueURL(in: outputFolder(for: url), base: url.deletingPathExtension().lastPathComponent + " (сжато)",
                            ext: "jpg")
        try writeJPEG(from: url, to: out, maxPixel: 2560, quality: 0.7)
        return out
    }

    /// В JPG без уменьшения (HEIC, PNG, TIFF…), качество 90%.
    static func convertToJPEG(_ url: URL) throws -> URL {
        guard isImage(url) else { throw Failure.notImage }
        let out = uniqueURL(in: outputFolder(for: url), base: url.deletingPathExtension().lastPathComponent, ext: "jpg")
        try writeJPEG(from: url, to: out, maxPixel: nil, quality: 0.9)
        return out
    }

    private static func writeJPEG(from url: URL, to out: URL, maxPixel: Int?, quality: Double) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure.cannotRead }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
        ]
        if let maxPixel {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
        } else if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(w, h)
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { throw Failure.cannotRead }
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.cannotWrite }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.cannotWrite }
    }

    /// Упаковать один или несколько файлов/папок в zip.
    static func zip(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw Failure.zipFailed }
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Архив"
        let out = uniqueURL(in: outputFolder(for: first), base: base, ext: "zip")
        if urls.count == 1 {
            try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path])
        } else {
            // Несколько файлов из разных папок: собираем ссылки во временной папке (zip идёт по ссылкам).
            let stage = FileManager.default.temporaryDirectory.appendingPathComponent("kuboring-zip-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stage) }
            var used: Set<String> = []
            for url in urls {
                var name = url.lastPathComponent
                var n = 2
                while used.contains(name) {
                    name = "\(url.deletingPathExtension().lastPathComponent) \(n)"
                        + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")
                    n += 1
                }
                used.insert(name)
                try FileManager.default.createSymbolicLink(at: stage.appendingPathComponent(name), withDestinationURL: url)
            }
            try run("/usr/bin/zip", ["-r", "-q", out.path, "."], cwd: stage)
        }
        guard FileManager.default.fileExists(atPath: out.path) else { throw Failure.zipFailed }
        return out
    }

    /// Переименовать на месте. Без расширения в новом имени — сохраняем старое.
    static func rename(_ url: URL, to rawName: String) throws -> URL {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") || name.count > 1, name != ".." else {
            throw Failure.badName
        }
        if (name as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty {
            name += ".\(url.pathExtension)"
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        if target.path == url.path { return url }
        // Смена только регистра — допустима на нечувствительной к регистру ФС.
        if FileManager.default.fileExists(atPath: target.path), target.path.lowercased() != url.path.lowercased() {
            throw Failure.nameTaken
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            throw Failure.cannotWrite
        }
        return target
    }

    // MARK: Вспомогательное

    private static func outputFolder(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: dir.path) { return dir }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? dir
    }

    static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    private static func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Failure.zipFailed }
    }
}
