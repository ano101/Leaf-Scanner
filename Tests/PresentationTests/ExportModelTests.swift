import CoreGraphics
import Foundation
import Testing
@testable import Leaf

@Suite("Экран экспорта")
@MainActor
struct ExportModelTests {
    private func makeModel(pageCount: Int = 2, detailed: Bool = false) -> ExportModel {
        let pages = (0..<pageCount).map { Page(order: $0, filter: .original) }
        let document = Document(name: "Договор", pages: pages)
        let source = StubImageSource(pages: pages, detailed: detailed)
        return ExportModel(document: document, fitter: SizeFitter(source: source))
    }

    @Test("выбор пресета подставляет его предел и цветовой режим")
    func choosingPresetAppliesItsLimitAndColorMode() {
        let model = makeModel()

        model.selectPreset("bank")

        #expect(model.limitBytes == 2 * 1_048_576)
        #expect(model.colorMode == .gray)
        #expect(model.isCustomLimit == false)
    }

    @Test("свободный размер берётся из ползунка")
    func customLimitComesFromTheSlider() {
        let model = makeModel()

        model.selectPreset(ExportPreset.customKey)
        model.customLimitMegabytes = 3

        #expect(model.isCustomLimit)
        #expect(model.limitBytes == 3 * 1_048_576)
    }

    @Test("готовый файл показывает вес до сохранения")
    func readyFileShowsItsSizeBeforeSaving() async {
        let model = makeModel()
        model.selectPreset(ExportPreset.customKey)
        model.customLimitMegabytes = 5

        await model.prepare()

        guard case let .ready(bytes, _) = model.outcome else {
            Issue.record("ожидался готовый файл, пришло \(model.outcome)")
            return
        }
        #expect(bytes > 0)
        #expect(model.data?.count == bytes)
    }

    @Test("недостижимый предел даёт предложение, а не тупик")
    func unreachableLimitGivesSuggestionNotDeadEnd() async {
        let model = makeModel(pageCount: 4, detailed: true)
        model.selectPreset(ExportPreset.customKey)
        model.customLimitMegabytes = 0.0005

        await model.prepare()

        guard case let .suggestion(_, achievable) = model.outcome else {
            Issue.record("ожидалось предложение сменить режим, пришло \(model.outcome)")
            return
        }
        #expect(achievable == .gray)
    }

    @Test("предложение принимается одним касанием и меняет режим")
    func suggestionIsAcceptedInOneTap() async {
        let model = makeModel(pageCount: 4, detailed: true)
        model.selectPreset(ExportPreset.customKey)
        model.customLimitMegabytes = 0.0005
        await model.prepare()

        await model.acceptSuggestion()

        #expect(model.colorMode != .color)
    }

    @Test("пароль с кириллицей объясняется до сборки, а не после")
    func cyrillicPasswordIsExplainedBeforeBuilding() async {
        let model = makeModel()
        model.password = "тайна"

        await model.prepare()

        #expect(model.outcome == .failed(messageKey: "export.error.password"))
        #expect(model.data == nil)
    }

    @Test("самая тяжёлая страница названа номером, а не идентификатором")
    func heaviestPageIsNamedByItsNumber() async {
        let model = makeModel(pageCount: 3)
        model.selectPreset(ExportPreset.customKey)
        model.customLimitMegabytes = 5

        await model.prepare()

        guard case let .ready(_, heaviest) = model.outcome else {
            Issue.record("ожидался готовый файл, пришло \(model.outcome)")
            return
        }
        #expect(heaviest != nil)
        #expect((1...3).contains(heaviest ?? 0))
    }
}

private struct StubImageSource: PageImageSource {
    private let images: [PageID: CGImage]

    init(pages: [Page], detailed: Bool) {
        var prepared: [PageID: CGImage] = [:]
        for page in pages {
            prepared[page.id] = detailed
                ? ImageFactory.noisy(width: 1200, height: 1600)
                : ImageFactory.halves(width: 600, height: 800)
        }
        images = prepared
    }

    func image(for id: PageID) async throws -> CGImage {
        guard let image = images[id] else { throw PageStoreError.pageNotFound(id) }
        return image
    }
}
