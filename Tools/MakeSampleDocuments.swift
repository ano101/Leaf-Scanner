import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Образцы документов для снимков в магазине.
//
// Настоящие документы заказчика использовать нельзя: снимки уходят в открытый
// магазин вместе с тем, что на них написано. Поэтому бумаги вымышленные,
// но выглядят как настоящие — иначе снимок не показывает продукт.

struct Line {
    let text: String
    let size: Double
    let bold: Bool
    let gap: Double

    init(_ text: String, size: Double = 15, bold: Bool = false, gap: Double = 10) {
        self.text = text
        self.size = size
        self.bold = bold
        self.gap = gap
    }
}

func render(_ lines: [Line], to path: String, width: Int = 1240, height: Int = 1754) {
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("нет холста") }

    // Бумага не идеально белая, и снятая телефоном — тем более.
    context.setFillColor(CGColor(red: 0.97, green: 0.965, blue: 0.95, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    var y = Double(height) - 140
    let left = 110.0

    for line in lines {
        let font = CTFontCreateWithName(
            (line.bold ? "Helvetica-Bold" : "Helvetica") as CFString,
            line.size * 2.2,
            nil
        )
        let attributed = NSAttributedString(
            string: line.text,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key:
                    CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
            ]
        )
        context.textPosition = CGPoint(x: left, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        y -= line.size * 2.2 + line.gap * 2.2
    }

    guard let image = context.makeImage() else { fatalError("нет изображения") }
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { fatalError("нет файла") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("не записалось") }
    print("готово:", path)
}

let output = CommandLine.arguments[1]

render([
    Line("ДОГОВОР АРЕНДЫ", size: 22, bold: true, gap: 6),
    Line("нежилого помещения № 14/2026", size: 14, gap: 26),
    Line("г. Москва                                        12 марта 2026 г.", size: 13, gap: 24),
    Line("1. ПРЕДМЕТ ДОГОВОРА", size: 15, bold: true, gap: 10),
    Line("1.1. Арендодатель передаёт, а Арендатор принимает во"),
    Line("временное владение и пользование нежилое помещение"),
    Line("общей площадью 84,5 кв. м, расположенное по адресу:"),
    Line("г. Москва, ул. Примерная, д. 7, помещение 3.", gap: 22),
    Line("2. СРОК ДЕЙСТВИЯ", size: 15, bold: true, gap: 10),
    Line("2.1. Договор заключён сроком на 11 месяцев и вступает"),
    Line("в силу с момента подписания обеими сторонами.", gap: 22),
    Line("3. АРЕНДНАЯ ПЛАТА", size: 15, bold: true, gap: 10),
    Line("3.1. Размер арендной платы составляет 145 000 рублей"),
    Line("в месяц, включая коммунальные платежи.", gap: 22),
    Line("3.2. Оплата производится до 5 числа каждого месяца."),
], to: "\(output)/contract.jpg")

render([
    Line("СЧЁТ НА ОПЛАТУ № 205", size: 22, bold: true, gap: 6),
    Line("от 18 марта 2026 г.", size: 14, gap: 26),
    Line("Поставщик: ООО «Пример Технологии»", gap: 6),
    Line("Покупатель: ИП Образцов А. А.", gap: 24),
    Line("№    Наименование работ                   Сумма", size: 14, bold: true, gap: 14),
    Line("1    Разработка программного модуля       180 000,00", size: 14),
    Line("2    Настройка и запуск                    45 000,00", size: 14),
    Line("3    Техническая поддержка, 3 мес.         36 000,00", size: 14, gap: 20),
    Line("Итого:                                    261 000,00", size: 15, bold: true, gap: 6),
    Line("НДС не облагается", size: 13, gap: 26),
    Line("Всего к оплате: двести шестьдесят одна тысяча", size: 14),
    Line("рублей 00 копеек.", size: 14),
], to: "\(output)/invoice.jpg")

render([
    Line("СПРАВКА", size: 22, bold: true, gap: 6),
    Line("о доходах за 2025 год", size: 14, gap: 30),
    Line("Выдана: Образцову Алексею Андреевичу", gap: 8),
    Line("Должность: инженер-программист", gap: 8),
    Line("Период: январь — декабрь 2025 г.", gap: 26),
    Line("Месяц                        Начислено", size: 14, bold: true, gap: 14),
    Line("Январь                       210 000,00", size: 14),
    Line("Февраль                      210 000,00", size: 14),
    Line("Март                         245 000,00", size: 14),
    Line("Апрель                       210 000,00", size: 14, gap: 20),
    Line("Справка выдана для предъявления по месту требования."),
], to: "\(output)/statement.jpg")
