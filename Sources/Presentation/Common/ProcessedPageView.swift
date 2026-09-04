import CoreGraphics
import SwiftUI

/// Страница такой, какой она уйдёт в файл.
///
/// Раньше на экране правки показывался исходный кадр, и поворот менял данные,
/// но на экране ничего не происходило — человек считал кнопку сломанной.
/// Показывать нужно результат, а не источник.
struct ProcessedPageView: View {
    let page: Page
    let look: PageLook
    let cache: PageRenderCache
    var maxSide: Int = 1400

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.pageCorner)
                .fill(Theme.paper)

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.pageCorner))
            } else {
                ProgressView()
            }
        }
        .task(id: identity) {
            image = await cache.image(for: page, look: look, maxSide: maxSide)
        }
    }

    /// Пересчёт запускается при любой правке страницы, а не только при смене
    /// самой страницы: иначе поворот снова стал бы невидимым.
    private var identity: String {
        "\(page.id)|\(look.rawValue)|\(page.rotation.rawValue)|\(page.redactions.count)|\(page.crop != nil)"
    }
}
