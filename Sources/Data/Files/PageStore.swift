import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PageStoreError: Error, Equatable, Sendable {
    case pageNotFound(PageID)
    case encodingFailed(PageID)
    case decodingFailed(PageID)
}

public protocol PageStoreProtocol: PageImageSource {
    func storeOriginal(_ image: CGImage, for id: PageID) async throws -> URL
    func original(for id: PageID) async throws -> CGImage
    func thumbnail(for id: PageID) async throws -> CGImage
    func remove(_ id: PageID) async throws
}

/// Пиксели живут на диске, а не в базе.
///
/// База отдаёт список из тысячи строк за миллисекунды именно потому, что
/// изображения через неё не проходят. Миниатюра готовится один раз при
/// сохранении и лежит отдельным файлом — список никогда не открывает
/// оригиналы.
public struct PageStore: PageStoreProtocol {
    public static let thumbnailSide = 320

    private let root: URL
    private let originals: URL
    private let thumbnails: URL

    public init(root: URL) throws {
        self.root = root
        self.originals = root.appendingPathComponent("originals", isDirectory: true)
        self.thumbnails = root.appendingPathComponent("thumbnails", isDirectory: true)

        for directory in [originals, thumbnails] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                // До первой разблокировки устройства файлы нечитаемы даже
                // при физическом доступе к накопителю.
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
        }
    }

    public func originalURL(for id: PageID) -> URL {
        originals.appendingPathComponent("\(id.raw.uuidString).heic")
    }

    public func thumbnailURL(for id: PageID) -> URL {
        thumbnails.appendingPathComponent("\(id.raw.uuidString).heic")
    }

    public func storeOriginal(_ image: CGImage, for id: PageID) async throws -> URL {
        let url = originalURL(for: id)
        try write(image, to: url, quality: 1.0, pageID: id)
        try writeThumbnail(from: image, for: id)
        return url
    }

    public func original(for id: PageID) async throws -> CGImage {
        try read(from: originalURL(for: id), pageID: id)
    }

    /// Тот же оригинал под именем, которым его спрашивают сборка файла
    /// и распознавание: им не нужно знать, что источник — диск.
    public func image(for id: PageID) async throws -> CGImage {
        try await original(for: id)
    }

    public func thumbnail(for id: PageID) async throws -> CGImage {
        try read(from: thumbnailURL(for: id), pageID: id)
    }

    public func originalByteCount(for id: PageID) async throws -> Int {
        let url = originalURL(for: id)
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else {
            throw PageStoreError.pageNotFound(id)
        }
        return size
    }

    /// Отсутствие файла — не ошибка: удаление повторяется при откате
    /// незавершённой съёмки, и падать на этом нечестно.
    public func remove(_ id: PageID) async throws {
        for url in [originalURL(for: id), thumbnailURL(for: id)] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func writeThumbnail(from image: CGImage, for id: PageID) throws {
        let longest = max(image.width, image.height)
        let factor = longest > Self.thumbnailSide
            ? Double(Self.thumbnailSide) / Double(longest)
            : 1.0

        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw PageStoreError.encodingFailed(id)
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let scaled = context.makeImage() else {
            throw PageStoreError.encodingFailed(id)
        }
        try write(scaled, to: thumbnailURL(for: id), quality: 0.8, pageID: id)
    }

    private func write(_ image: CGImage, to url: URL, quality: Double, pageID: PageID) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw PageStoreError.encodingFailed(pageID)
        }

        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)

        guard CGImageDestinationFinalize(destination) else {
            throw PageStoreError.encodingFailed(pageID)
        }

        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
    }

    private func read(from url: URL, pageID: PageID) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PageStoreError.pageNotFound(pageID)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PageStoreError.decodingFailed(pageID)
        }
        return image
    }
}
