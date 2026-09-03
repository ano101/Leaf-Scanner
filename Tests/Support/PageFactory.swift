import Foundation
@testable import Leaf

/// Фикстуры страниц. Порядок задаётся индексом, чтобы тесты могли
/// проверять перестановки, не заботясь об остальных полях.
enum PageFactory {
    static func pages(count: Int) -> [Page] {
        (0..<count).map { index in
            Page(id: PageID(), order: index)
        }
    }

    static func page(order: Int = 0, rotation: Rotation = .none) -> Page {
        Page(id: PageID(), order: order, rotation: rotation)
    }
}
