import CoreGraphics
import SwiftUI

/// Правка одной страницы: поворот, вид и замазка.
///
/// Найденные персональные данные показываются рамками, которые закрываются
/// одним касанием. Свою область можно обвести пальцем — распознавание видит
/// не всё, и человек не должен упираться в границы того, что нашла машина.
struct PageEditorView: View {
    let pageID: PageID
    let model: DocumentModel
    let services: AppServices

    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var suggestions: [SensitiveMatch] = []
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    private var page: Page? {
        model.pages.first { $0.id == pageID }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheet
            controls
        }
        .navigationTitle("document.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.done") { dismiss() }
            }
        }
        .task {
            image = try? await services.store.original(for: pageID)
            await loadSuggestions()
        }
    }

    private var sheet: some View {
        GeometryReader { geometry in
            let frame = fittedFrame(in: geometry.size)

            ZStack(alignment: .topLeading) {
                Color.clear

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                overlays(in: frame)
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(in: frame))
        }
        .background(Theme.paper)
    }

    /// Лист вписан в экран с сохранением пропорций, поэтому доли страницы
    /// пересчитываются в координаты именно этого прямоугольника, а не всего
    /// экрана. Иначе замазка ложилась бы мимо: человек закрыл бы номер,
    /// а закрылось бы поле рядом.
    private func fittedFrame(in size: CGSize) -> CGRect {
        guard let image, image.width > 0, image.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }

        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let screenAspect = size.width / size.height

        if imageAspect > screenAspect {
            let height = size.width / imageAspect
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }

        let width = size.height * imageAspect
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
    }

    @ViewBuilder
    private func overlays(in frame: CGRect) -> some View {
        if let page {
            ForEach(page.redactions) { area in
                Rectangle()
                    .fill(.black)
                    .frame(width: area.rect.width * frame.width, height: area.rect.height * frame.height)
                    .position(
                        x: frame.minX + (area.rect.x + area.rect.width / 2) * frame.width,
                        y: frame.minY + (area.rect.y + area.rect.height / 2) * frame.height
                    )
            }
        }

        ForEach(suggestions) { match in
            Rectangle()
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .frame(width: match.box.width * frame.width, height: match.box.height * frame.height)
                .position(
                    x: frame.minX + (match.box.x + match.box.width / 2) * frame.width,
                    y: frame.minY + (match.box.y + match.box.height / 2) * frame.height
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await model.addRedaction(RedactionArea(rect: match.box), to: pageID) }
                }
        }

        if let start = dragStart, let current = dragCurrent {
            Rectangle()
                .fill(.black.opacity(0.55))
                .frame(width: abs(current.x - start.x), height: abs(current.y - start.y))
                .position(x: (start.x + current.x) / 2, y: (start.y + current.y) / 2)
        }
    }

    private func drawGesture(in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                let start = dragStart
                dragStart = nil
                dragCurrent = nil

                guard let start, frame.width > 0, frame.height > 0 else { return }

                let minX = (min(start.x, value.location.x) - frame.minX) / frame.width
                let minY = (min(start.y, value.location.y) - frame.minY) / frame.height
                let width = abs(value.location.x - start.x) / frame.width
                let height = abs(value.location.y - start.y) / frame.height

                let rect = NormalizedRect(
                    x: max(0, min(1, minX)),
                    y: max(0, min(1, minY)),
                    width: min(width, 1),
                    height: min(height, 1)
                )
                // Случайное касание не должно оставлять на листе чёрную точку.
                guard rect.width > 0.02, rect.height > 0.01 else { return }

                Task { await model.addRedaction(RedactionArea(rect: rect), to: pageID) }
            }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if suggestions.isEmpty == false {
                Text("document.redaction.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.rotateRight(pageID) }
                } label: {
                    Label("document.rotate", systemImage: "rotate.right")
                }

                Menu {
                    ForEach(PageFilter.allCases, id: \.self) { filter in
                        Button(LocalizedStringKey("filter.\(filter.rawValue)")) {
                            Task { await model.setFilter(filter, for: pageID) }
                        }
                    }
                } label: {
                    Label("document.filter", systemImage: "wand.and.stars")
                }

                Button(role: .destructive) {
                    Task { await model.removeRedactions(from: pageID) }
                } label: {
                    Label("document.redaction.clear", systemImage: "eye")
                }
                .disabled(page?.redactions.isEmpty ?? true)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .labelStyle(.iconOnly)
            .font(.title3)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func loadSuggestions() async {
        guard let text = page?.recognizedText, text.isEmpty == false else { return }

        let rows = text.split(separator: "\n")
        let height = 1.0 / Double(max(rows.count, 1))
        let lines = rows.enumerated().map { index, row in
            RecognizedLine(
                text: String(row),
                box: NormalizedRect(x: 0.05, y: Double(index) * height, width: 0.9, height: height * 0.8)
            )
        }

        suggestions = SensitiveDataDetector().detect(in: lines)
    }
}
