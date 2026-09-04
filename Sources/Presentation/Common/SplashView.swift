import SwiftUI

/// Заставка на время запуска.
///
/// Сделана на SwiftUI, без сторонней библиотеки: у приложения ровно одна
/// зависимость, взятая ради поиска, и тянуть вторую ради нескольких секунд
/// анимации — это лишний вес в пакете и лишний повод для поломки при
/// обновлении системы.
///
/// Главное правило заставки: она не имеет права задерживать. Как только
/// архив готов, она уходит, даже если анимация не доиграла. Заставка,
/// заставляющая ждать, хуже её отсутствия.
struct SplashView: View {
    @State private var bracketsIn = false
    @State private var sheetIn = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.40, blue: 0.31),
                    Color(red: 0.10, green: 0.27, blue: 0.21),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ZStack {
                sheet
                    .opacity(sheetIn ? 1 : 0)
                    .scaleEffect(sheetIn ? 1 : 0.86)

                brackets
                    .opacity(bracketsIn ? 1 : 0)
                    .scaleEffect(bracketsIn ? 1 : 1.4)
            }
            .frame(width: 168, height: 168)

            VStack {
                Spacer()
                Text(verbatim: AppInfo.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(sheetIn ? 0.9 : 0))
                    .padding(.bottom, 56)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.45)) { sheetIn = true }
            withAnimation(.spring(duration: 0.55).delay(0.1)) { bracketsIn = true }
        }
    }

    private var sheet: some View {
        ZStack(alignment: .topLeading) {
            FoldedSheet()
                .fill(.white)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<4, id: \.self) { row in
                    Capsule()
                        .fill(Color(white: 0.72))
                        .frame(width: row == 3 ? 32 : 52, height: 5)
                }
            }
            .padding(.leading, 18)
            .padding(.top, 46)
        }
        .frame(width: 84, height: 108)
    }

    private var brackets: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { corner in
                Bracket()
                    .stroke(Color(red: 0.62, green: 0.90, blue: 0.76), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(Double(corner) * 90))
                    .offset(
                        x: corner == 1 || corner == 2 ? 67 : -67,
                        y: corner >= 2 ? 67 : -67
                    )
            }
        }
    }
}

/// Лист со скошенным углом — тот же силуэт, что на иконке.
private struct FoldedSheet: Shape {
    func path(in rect: CGRect) -> Path {
        let corner = rect.width * 0.3
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Bracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
