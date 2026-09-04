import CoreGraphics
import Testing
@testable import Leaf

/// Проверки вида «как из сканера».
///
/// Разница между «подтянуть контраст» и «выровнять освещение» видна только
/// на снимке с неровным светом — на ровной фикстуре оба дают одно и то же,
/// и проверка ничего не докажет.
@Suite("Вид страницы: как из сканера")
struct ScannerLookTests {
    private let renderer = PageRenderer()

    private let leftHalf = CGRect(x: 0.02, y: 0.02, width: 0.44, height: 0.96)
    private let rightHalf = CGRect(x: 0.54, y: 0.02, width: 0.44, height: 0.96)

    private func page(look: PageLook) -> Page {
        Page(id: PageID(), order: 0, look: look)
    }

    private func render(_ look: PageLook) throws -> CGImage {
        try renderer.render(
            ImageFactory.shadowedDocument(),
            page: page(look: look),
            look: look,
            scale: 1.0
        )
    }

    @Test("фикстура действительно снята при неровном свете")
    func fixtureReallyHasUnevenLight() {
        let source = ImageFactory.shadowedDocument()
        let left = PixelSampler.averageLuminance(of: source, in: leftHalf)
        let right = PixelSampler.averageLuminance(of: source, in: rightHalf)

        // Без этого расхождения весь набор ниже проверял бы пустоту.
        #expect(right - left > 60, "тень на фикстуре слишком слабая: \(left) против \(right)")
    }

    @Test("цветной скан выравнивает освещение по всему листу")
    func colorScanEvensOutLighting() throws {
        let result = try render(.color)

        let left = PixelSampler.averageLuminance(of: result, in: leftHalf)
        let right = PixelSampler.averageLuminance(of: result, in: rightHalf)

        #expect(abs(right - left) < 25, "тень осталась: \(left) против \(right)")
    }

    @Test("бумага после обработки выходит в белое, а не в серое")
    func paperComesOutWhiteNotGray() throws {
        let result = try render(.color)
        // Поля листа — чистая бумага без текста.
        let margin = CGRect(x: 0.0, y: 0.0, width: 0.08, height: 0.9)

        #expect(PixelSampler.averageLuminance(of: result, in: margin) > 230)
    }

    @Test("текст остаётся тёмным — выравнивание не размывает документ")
    func textStaysDark() throws {
        let result = try render(.color)
        let paper = PixelSampler.averageLuminance(of: result, in: CGRect(x: 0, y: 0, width: 0.08, height: 0.9))
        let body = PixelSampler.averageLuminance(of: result, in: CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8))

        #expect(paper - body > 40, "текст перестал отличаться от бумаги")
    }

    @Test("чёрно-белый не съедает затенённую половину листа")
    func blackAndWhiteDoesNotEatTheShadowedHalf() throws {
        // Именно это ломается при общем пороге яркости: тень уходит в чёрное
        // целиком, и режим, который берут ради лёгкого файла, портит документ.
        let result = try render(.blackAndWhite)

        let darkLeft = PixelSampler.darkShare(of: result, in: leftHalf)
        let darkRight = PixelSampler.darkShare(of: result, in: rightHalf)

        #expect(darkLeft < 0.5, "затенённая половина ушла в чёрное: \(darkLeft)")
        #expect(abs(darkLeft - darkRight) < 0.25, "половины разошлись: \(darkLeft) против \(darkRight)")
    }

    @Test("чёрно-белый оставляет ровно два уровня яркости")
    func blackAndWhiteLeavesExactlyTwoLevels() throws {
        #expect(PixelSampler.luminanceLevels(of: try render(.blackAndWhite)).count <= 2)
    }

    @Test("серый скан убирает цвет, но сохраняет полутона")
    func grayScanRemovesColourKeepsShades() throws {
        #expect(PixelSampler.luminanceLevels(of: try render(.gray)).count > 2)
    }

    @Test("«как снято» ничего не выравнивает — фотография остаётся фотографией")
    func asShotChangesNothing() throws {
        let result = try render(.asShot)

        let left = PixelSampler.averageLuminance(of: result, in: leftHalf)
        let right = PixelSampler.averageLuminance(of: result, in: rightHalf)

        #expect(right - left > 60, "вид «как снято» не имеет права трогать освещение")
    }
}

@Suite("Словарь видов страницы")
struct PageLookTests {
    @Test("виды идут от тяжёлого к лёгкому")
    func looksGoFromHeavyToLight() {
        #expect(PageLook.color.lighter == .gray)
        #expect(PageLook.gray.lighter == .blackAndWhite)
        #expect(PageLook.blackAndWhite.lighter == nil)
    }

    @Test("«как снято» спускается к цветному скану, а не в никуда")
    func asShotStepsDownToColourScan() {
        // Иначе предложение «сделать легче» на фотографии обрывалось бы
        // отказом, хотя облегчить её есть чем.
        #expect(PageLook.asShot.lighter == .color)
    }

    @Test("у каждого вида есть ключ перевода")
    func everyLookHasATranslationKey() {
        for look in PageLook.allCases {
            #expect(look.titleKey == "look.\(look.rawValue)")
        }
    }
}
