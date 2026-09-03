import CoreGraphics
import Foundation
import Vision

public protocol TextRecognizerProtocol: Sendable {
    func recognize(_ image: CGImage) async throws -> [RecognizedLine]
}

/// Распознавание текста на устройстве.
///
/// Это та самая работа, за которую конкуренты берут подписку. Vision делает
/// её бесплатно и не отправляя изображение никуда, поэтому у приложения нет
/// ни повода, ни возможности брать за неё деньги.
public struct TextRecognizer: TextRecognizerProtocol {
    private let languages: [Locale.Language]

    public init(languages: [Locale.Language] = [
        Locale.Language(identifier: "ru-RU"),
        Locale.Language(identifier: "en-US"),
    ]) {
        self.languages = languages
    }

    public func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: image)

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }

            let box = observation.boundingBox.cgRect
            return RecognizedLine(
                text: candidate.string,
                box: .init(
                    x: Double(box.minX),
                    // Vision отсчитывает снизу, страница и замазка — сверху.
                    y: Double(1 - box.maxY),
                    width: Double(box.width),
                    height: Double(box.height)
                )
            )
        }
    }

    /// Текст для поиска: порядок строк сохраняется, чтобы найденный фрагмент
    /// читался так же, как на листе.
    public static func plainText(from lines: [RecognizedLine]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }
}
