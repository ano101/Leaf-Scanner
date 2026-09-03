import Foundation

/// Распознавание текста после съёмки.
///
/// Работает отдельно от съёмки нарочно: разбор страницы занимает секунды,
/// и держать на нём экран значило бы превратить съёмку пачки в ожидание.
/// Документ доступен сразу, текст появляется чуть позже.
public actor TextRecognitionWorker {
    private let images: any PageImageSource
    private let recognizer: any TextRecognizerProtocol
    private let documents: any DocumentRepositoryProtocol

    public init(
        images: any PageImageSource,
        recognizer: any TextRecognizerProtocol,
        documents: any DocumentRepositoryProtocol
    ) {
        self.images = images
        self.recognizer = recognizer
        self.documents = documents
    }

    public func process(documentID: DocumentID) async throws {
        // Документ мог быть удалён, пока страница ждала очереди. Это обычный
        // ход событий, а не ошибка.
        guard var document = try await documents.document(documentID) else { return }

        var changed = false

        for index in document.pages.indices where document.pages[index].recognizedText == nil {
            let page = document.pages[index]

            do {
                let image = try await images.image(for: page.id)
                let lines = try await recognizer.recognize(image)
                document.pages[index].recognizedText = TextRecognizer.plainText(from: lines)
                changed = true
            } catch {
                // Неудача разбора одной страницы не должна отменять работу
                // над остальными и тем более портить документ. Текст просто
                // не появится, документ останется рабочим.
                continue
            }
        }

        guard changed else { return }
        try await documents.save(document)
    }
}
