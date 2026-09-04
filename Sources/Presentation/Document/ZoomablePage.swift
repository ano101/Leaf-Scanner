import SwiftUI

/// Страница, которую можно приблизить.
///
/// Человек открывает документ чаще всего чтобы прочитать мелкий шрифт —
/// печать, номер, приписку от руки. Экран без увеличения заставляет его
/// выйти и открыть тот же файл в другом приложении.
struct ZoomablePage: View {
    let page: Page
    let look: PageLook
    let cache: PageRenderCache

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maximumZoom: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ProcessedPageView(page: page, look: look, cache: cache)
                .scaleEffect(zoom)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(magnification)
                .simultaneousGesture(pan(in: geometry.size))
                .onTapGesture(count: 2) { toggleZoom() }
                .onChange(of: page.id) { _, _ in reset() }
        }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value.magnification, 1), maximumZoom)
            }
            .onEnded { _ in
                committedZoom = zoom
                if zoom <= 1 { reset() }
            }
    }

    /// Двигать страницу можно только когда она приближена: иначе жест
    /// перехватывал бы листание между страницами.
    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard committedZoom > 1 else { return }
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard committedZoom > 1 else { return }
                offset = clamped(offset, in: size)
                committedOffset = offset
            }
    }

    /// Страницу нельзя утащить за край: пустой экран вместо документа
    /// человек читает как потерю страницы.
    private func clamped(_ value: CGSize, in size: CGSize) -> CGSize {
        let limitX = size.width * (committedZoom - 1) / 2
        let limitY = size.height * (committedZoom - 1) / 2

        return CGSize(
            width: min(max(value.width, -limitX), limitX),
            height: min(max(value.height, -limitY), limitY)
        )
    }

    private func toggleZoom() {
        withAnimation(.snappy) {
            if committedZoom > 1 {
                reset()
            } else {
                committedZoom = 2.5
                zoom = 2.5
            }
        }
    }

    private func reset() {
        zoom = 1
        committedZoom = 1
        offset = .zero
        committedOffset = .zero
    }
}
