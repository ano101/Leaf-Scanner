import CoreGraphics
import Foundation
import Testing
@testable import Leaf

@Suite("Хранилище страниц на диске")
struct PageStoreTests {
    private func makeStore() throws -> (PageStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leaf-tests-\(UUID().uuidString)")
        return (try PageStore(root: root), root)
    }

    @Test("сохранённый оригинал читается обратно тех же размеров")
    func storedOriginalComesBackAtSameSize() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = PageID()

        _ = try await store.storeOriginal(ImageFactory.solid(width: 400, height: 300), for: id)
        let restored = try await store.original(for: id)

        #expect(restored.width == 400)
        #expect(restored.height == 300)
    }

    @Test("миниатюра не длиннее заданной стороны")
    func thumbnailFitsRequestedSide() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = PageID()

        _ = try await store.storeOriginal(ImageFactory.solid(width: 2000, height: 1000), for: id)
        let thumbnail = try await store.thumbnail(for: id)

        #expect(max(thumbnail.width, thumbnail.height) <= PageStore.thumbnailSide)
        #expect(thumbnail.width > thumbnail.height)
    }

    @Test("миниатюра готовится при сохранении, а не при первом показе списка")
    func thumbnailIsPreparedOnSaveNotOnFirstShow() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = PageID()

        _ = try await store.storeOriginal(ImageFactory.solid(width: 1200, height: 900), for: id)

        #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: id).path))
    }

    @Test("удаление уносит и оригинал, и миниатюру")
    func removingTakesBothFiles() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = PageID()
        _ = try await store.storeOriginal(ImageFactory.solid(width: 100, height: 100), for: id)

        try await store.remove(id)

        #expect(FileManager.default.fileExists(atPath: store.originalURL(for: id).path) == false)
        #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: id).path) == false)
    }

    @Test("чтение отсутствующей страницы даёт внятную ошибку, а не пустоту")
    func readingMissingPageGivesTypedError() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: PageStoreError.self) {
            _ = try await store.original(for: PageID())
        }
    }

    @Test("повторное удаление не считается ошибкой")
    func removingTwiceIsNotAnError() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = PageID()
        _ = try await store.storeOriginal(ImageFactory.solid(width: 50, height: 50), for: id)

        try await store.remove(id)
        try await store.remove(id)
    }

    @Test("вес сохранённой страницы известен без чтения изображения")
    func storedPageSizeIsKnownWithoutDecoding() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = PageID()
        _ = try await store.storeOriginal(ImageFactory.halves(width: 800, height: 600), for: id)

        let bytes = try await store.originalByteCount(for: id)
        #expect(bytes > 0)
    }
}
