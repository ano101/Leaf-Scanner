import Foundation

/// Экран, ради которого написано приложение: файл нужного веса.
///
/// Ни одно состояние здесь не заканчивается надписью без действия. Не влезает
/// в цвете — предлагается серый. Не влезает в чёрно-белом — показывается
/// достижимый вес и самая тяжёлая страница, с которой можно что-то сделать.
@MainActor
@Observable
public final class ExportModel {
    public enum Outcome: Equatable, Sendable {
        case idle
        case working
        case ready(bytes: Int, heaviestPageNumber: Int?)
        case suggestion(PageLook, achievableIn: PageLook)
        case impossible(bestBytes: Int, heaviestPageNumber: Int?)
        case failed(messageKey: String)
    }

    public private(set) var outcome: Outcome = .idle
    public private(set) var data: Data?

    public var presetID: String = ExportPreset.all.first?.id ?? ExportPreset.customKey
    public var customLimitMegabytes: Double = 1.0
    public var look: PageLook = .color
    public var password: String = ""

    private let document: Document
    private let fitter: SizeFitter
    /// Какие страницы уходят. Пусто — значит весь документ: человек,
    /// ничего не выделявший, ждёт целый документ, а не пустой файл.
    public let pageIDs: Set<PageID>?

    public var pages: [Page] {
        let ordered = PageOrdering.sorted(document.pages)
        guard let pageIDs, pageIDs.isEmpty == false else { return ordered }
        return PageOrdering.renumbered(ordered.filter { pageIDs.contains($0.id) })
    }

    public var isPartial: Bool {
        pages.count < document.pages.count
    }

    public init(document: Document, pageIDs: Set<PageID>? = nil, fitter: SizeFitter) {
        self.document = document
        self.pageIDs = pageIDs
        self.fitter = fitter

        if let preset = ExportPreset.all.first {
            presetID = preset.id
            look = preset.look
        }
        // Вид по умолчанию берётся у самого документа: человек уже выбрал
        // его на странице, и переспрашивать одно и то же незачем.
        if let first = document.pages.first {
            look = first.look
        }
    }

    public var presets: [ExportPreset] { ExportPreset.all }

    public var selectedPreset: ExportPreset? {
        ExportPreset.all.first { $0.id == presetID }
    }

    public var isCustomLimit: Bool {
        selectedPreset?.limitBytes == nil
    }

    public var limitBytes: Int {
        if let limit = selectedPreset?.limitBytes { return limit }
        return max(Int(customLimitMegabytes * 1_048_576), 1)
    }

    public func selectPreset(_ id: String) {
        presetID = id
        if let preset = ExportPreset.all.first(where: { $0.id == id }) {
            look = preset.look
        }
    }

    /// Предложение «попробуйте серый» принимается одним касанием: заставлять
    /// человека самого искать переключатель после отказа — это перекладывать
    /// на него работу приложения.
    public func acceptSuggestion() async {
        guard case let .suggestion(_, achievable) = outcome else { return }
        look = achievable
        await prepare()
    }

    public func prepare() async {
        if password.isEmpty == false, PDFBuilder.isRepresentable(password) == false {
            outcome = .failed(messageKey: "export.error.password")
            return
        }

        outcome = .working
        data = nil

        do {
            let result = try await fitter.fit(
                pages: pages,
                text: recognizedLines(),
                limitBytes: limitBytes,
                look: look,
                password: password.isEmpty ? nil : password
            )

            switch result {
            case let .fitted(fitted):
                data = fitted.data
                outcome = .ready(bytes: fitted.bytes, heaviestPageNumber: number(of: fitted.heaviestPageID))
            case let .needsLighterLook(suggestion):
                outcome = .suggestion(look, achievableIn: suggestion)
            case let .impossible(bestBytes):
                outcome = .impossible(bestBytes: bestBytes, heaviestPageNumber: nil)
            }
        } catch {
            outcome = .failed(messageKey: "export.error.build")
        }
    }

    /// Распознанный текст кладётся в файл невидимым слоем: документ ищется
    /// у получателя, а не только в этом приложении.
    private func recognizedLines() -> [PageID: [RecognizedLine]] {
        var lines: [PageID: [RecognizedLine]] = [:]

        for page in pages {
            guard let text = page.recognizedText, text.isEmpty == false else { continue }

            let rows = text.split(separator: "\n")
            let height = 1.0 / Double(max(rows.count, 1))

            lines[page.id] = rows.enumerated().map { index, row in
                RecognizedLine(
                    text: String(row),
                    box: NormalizedRect(x: 0.05, y: Double(index) * height, width: 0.9, height: height * 0.8)
                )
            }
        }

        return lines
    }

    private func number(of pageID: PageID?) -> Int? {
        guard let pageID else { return nil }
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else {
            return nil
        }
        return index + 1
    }
}
