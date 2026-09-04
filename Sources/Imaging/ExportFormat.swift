import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Во что превращается документ на выходе.
///
/// JPEG по странице нужен не для красоты: половина учреждений принимает
/// только изображения, и человек, у которого есть лишь PDF, идёт искать
/// сторонний конвертер.
public enum ExportFormat: String, Sendable, CaseIterable, Codable {
    case pdf
    case jpeg

    public var titleKey: String { "export.format.\(rawValue)" }

    public var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .jpeg: "jpg"
        }
    }
}

/// Готовый файл: имя и содержимое. PDF даёт один, JPEG — по одному
/// на страницу.
public struct ExportFile: Sendable, Identifiable {
    public let name: String
    public let data: Data

    public var id: String { name }

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public enum JPEGWriter {
    public static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PDFBuildError.contextCreationFailed
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw PDFBuildError.contextCreationFailed
        }

        return data as Data
    }
}
