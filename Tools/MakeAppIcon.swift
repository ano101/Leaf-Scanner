import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Иконка рисуется кодом, а не лежит разовым файлом: её можно перерисовать
// в другом размере или цвете, не открывая графический редактор, и видно,
// из чего она состоит.
//
// Замысел: белый лист со скошенным углом внутри скобок видоискателя.
// Скобки читаются как «сканер» с первого взгляда даже в размере значка
// на домашнем экране, скошенный угол отсылает к имени.

let side = 1024.0

guard let context = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("не удалось создать холст иконки")
}

// Фон: зелень приложения с лёгким уходом в темноту книзу.
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(red: 0.16, green: 0.40, blue: 0.31, alpha: 1),
        CGColor(red: 0.10, green: 0.27, blue: 0.21, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: side, y: 0),
    options: []
)

// Лист со скошенным правым верхним углом.
let sheetWidth = side * 0.44
let sheetHeight = side * 0.56
let sheetX = (side - sheetWidth) / 2
let sheetY = (side - sheetHeight) / 2
let corner = sheetWidth * 0.28

let sheet = CGMutablePath()
sheet.move(to: CGPoint(x: sheetX, y: sheetY))
sheet.addLine(to: CGPoint(x: sheetX + sheetWidth, y: sheetY))
sheet.addLine(to: CGPoint(x: sheetX + sheetWidth, y: sheetY + sheetHeight - corner))
sheet.addLine(to: CGPoint(x: sheetX + sheetWidth - corner, y: sheetY + sheetHeight))
sheet.addLine(to: CGPoint(x: sheetX, y: sheetY + sheetHeight))
sheet.closeSubpath()

context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.addPath(sheet)
context.fillPath()

// Загнутый уголок — тень того же зелёного, чтобы лист читался как бумага.
let fold = CGMutablePath()
fold.move(to: CGPoint(x: sheetX + sheetWidth - corner, y: sheetY + sheetHeight))
fold.addLine(to: CGPoint(x: sheetX + sheetWidth - corner, y: sheetY + sheetHeight - corner))
fold.addLine(to: CGPoint(x: sheetX + sheetWidth, y: sheetY + sheetHeight - corner))
fold.closeSubpath()

context.setFillColor(CGColor(red: 0.75, green: 0.85, blue: 0.80, alpha: 1))
context.addPath(fold)
context.fillPath()

// Строки текста на листе: без них белый прямоугольник не читается как документ.
context.setFillColor(CGColor(red: 0.62, green: 0.68, blue: 0.65, alpha: 1))
let lineHeight = sheetHeight * 0.045
for row in 0..<5 {
    let width = row == 4 ? sheetWidth * 0.4 : sheetWidth * 0.62
    context.fill(CGRect(
        x: sheetX + sheetWidth * 0.19,
        y: sheetY + sheetHeight * 0.62 - Double(row) * lineHeight * 2.1,
        width: width,
        height: lineHeight
    ))
}

// Скобки видоискателя.
let inset = side * 0.14
let armLength = side * 0.13
let thickness = side * 0.035
context.setStrokeColor(CGColor(red: 0.62, green: 0.90, blue: 0.76, alpha: 1))
context.setLineWidth(thickness)
context.setLineCap(.round)

for (x, y, dx, dy) in [
    (inset, inset, 1.0, 1.0),
    (side - inset, inset, -1.0, 1.0),
    (inset, side - inset, 1.0, -1.0),
    (side - inset, side - inset, -1.0, -1.0),
] {
    context.move(to: CGPoint(x: x + dx * armLength, y: y))
    context.addLine(to: CGPoint(x: x, y: y))
    context.addLine(to: CGPoint(x: x, y: y + dy * armLength))
    context.strokePath()
}

guard let image = context.makeImage() else { fatalError("не удалось получить иконку") }

let output = URL(fileURLWithPath: CommandLine.arguments[1])
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("не удалось создать файл иконки")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("не удалось записать иконку") }

print("иконка записана: \(output.path)")
