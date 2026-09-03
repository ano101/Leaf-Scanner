import CoreGraphics
import Foundation
import SwiftUI

/// Хранилище миниатюр в памяти.
///
/// Список прокручивается пальцем, и каждый повторный проход по одной и той же
/// строке не должен снова читать файл с диска. Кэш ограничен по числу
/// записей: архив может быть большим, а память — нет.
public actor ThumbnailLoader {
    private let store: any PageStoreProtocol
    private var cache: [PageID: CGImage] = [:]
    private var order: [PageID] = []
    private let capacity: Int

    public init(store: any PageStoreProtocol, capacity: Int = 200) {
        self.store = store
        self.capacity = capacity
    }

    public func thumbnail(for id: PageID) async -> CGImage? {
        if let cached = cache[id] { return cached }

        guard let image = try? await store.thumbnail(for: id) else { return nil }

        cache[id] = image
        order.append(id)

        if order.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }

        return image
    }

    public func forget(_ id: PageID) {
        cache[id] = nil
        order.removeAll { $0 == id }
    }
}

/// Миниатюра страницы. Пока изображения нет, показывается подложка листа,
/// а не пустое место: прыгающая вёрстка при прокрутке раздражает сильнее,
/// чем ожидание.
public struct PageThumbnail: View {
    private let pageID: PageID
    private let loader: ThumbnailLoader
    @State private var image: CGImage?

    public init(pageID: PageID, loader: ThumbnailLoader) {
        self.pageID = pageID
        self.loader = loader
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.pageCorner)
                .fill(Theme.paper)

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.pageCorner))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.pageCorner)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .task(id: pageID) {
            image = await loader.thumbnail(for: pageID)
        }
    }
}
