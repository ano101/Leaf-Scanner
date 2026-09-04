import CoreGraphics
import Foundation

/// Готовые к показу страницы.
///
/// Одна и та же страница нужна экрану по многу раз: при листании, при
/// возврате назад, при показе примеров видов. Каждый раз читать оригинал
/// с диска и прогонять через Core Image — это заметная глазом задержка,
/// поэтому результат держится в памяти.
///
/// Ключ включает всё, от чего зависит картинка. Забыть в нём поворот или
/// вид означало бы показывать человеку прошлое состояние страницы — самый
/// неприятный вид ошибки: приложение выглядит сломанным, хотя данные верны.
public actor PageRenderCache {
    private let store: any PageStoreProtocol
    private let renderer = PageRenderer()
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []
    private let capacity: Int

    public init(store: any PageStoreProtocol, capacity: Int = 40) {
        self.store = store
        self.capacity = capacity
    }

    public func image(for page: Page, look: PageLook, maxSide: Int) async -> CGImage? {
        let key = signature(of: page, look: look, maxSide: maxSide)
        if let ready = cache[key] { return ready }

        guard let original = try? await store.original(for: page.id) else { return nil }

        let longest = max(original.width, original.height)
        let scale = longest > maxSide ? Double(maxSide) / Double(longest) : 1.0

        guard let rendered = try? renderer.render(original, page: page, look: look, scale: scale) else {
            return nil
        }

        remember(rendered, as: key)
        return rendered
    }

    /// Сбрасывает всё, что относится к странице: после правки прежние
    /// картинки не имеют права всплыть.
    public func forget(_ pageID: PageID) {
        let prefix = pageID.raw.uuidString
        for key in order where key.hasPrefix(prefix) {
            cache[key] = nil
        }
        order.removeAll { $0.hasPrefix(prefix) }
    }

    private func remember(_ image: CGImage, as key: String) {
        cache[key] = image
        order.append(key)

        if order.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
    }

    private func signature(of page: Page, look: PageLook, maxSide: Int) -> String {
        let redactions = page.redactions
            .map { "\($0.rect.x),\($0.rect.y),\($0.rect.width),\($0.rect.height)" }
            .joined(separator: ";")
        let crop = page.crop.map { "\($0.topLeft.x),\($0.topLeft.y),\($0.bottomRight.x),\($0.bottomRight.y)" } ?? "-"

        return "\(page.id.raw.uuidString)|\(look.rawValue)|\(page.rotation.rawValue)|\(crop)|\(redactions)|\(maxSide)"
    }
}
