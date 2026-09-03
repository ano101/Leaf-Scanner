import CoreGraphics
import Foundation

/// Приём кадров из камеры.
///
/// Здесь делается только то, без чего страницу нельзя показать: запись
/// оригинала и отпечаток для поиска повторов. Распознавание текста стоит
/// секунды на страницу и уходит в фон — иначе съёмка пачки из двадцати
/// листов превратилась бы в ожидание.
public struct ScanImporter: Sendable {
    public static let maxNameLength = 60

    private let store: any PageStoreProtocol

    public init(store: any PageStoreProtocol) {
        self.store = store
    }

    public func makePages(from images: [CGImage], startingAt order: Int = 0) async throws -> [Page] {
        var pages: [Page] = []
        pages.reserveCapacity(images.count)

        for (offset, image) in images.enumerated() {
            let page = Page(
                order: order + offset,
                perceptualHash: PerceptualHash.hash(image)
            )
            _ = try await store.storeOriginal(image, for: page.id)
            pages.append(page)
        }

        return pages
    }

    /// Имя документа предлагается сразу, чтобы в архиве не появлялось строк
    /// «Без названия»: безымянный документ невозможно найти глазами.
    public static func suggestedName(from recognizedText: String?, date: Date) -> String {
        heading(from: recognizedText) ?? DateFormatter.documentName.string(from: date)
    }

    /// Заголовок, найденный на листе, — или ничего.
    ///
    /// Отделено от предложения имени нарочно: уточнять название задним числом
    /// можно только настоящим заголовком. Подстановка даты вместо него стёрла
    /// бы осмысленное имя и выглядела бы как потеря названия.
    public static func heading(from recognizedText: String?) -> String? {
        let firstMeaningfulLine = recognizedText?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count >= 3 }

        guard let firstMeaningfulLine else { return nil }

        guard firstMeaningfulLine.count > maxNameLength else { return firstMeaningfulLine }
        return String(firstMeaningfulLine.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }
}

extension DateFormatter {
    static let documentName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
