import Foundation

/// Сборка зависимостей в одном месте. Синглтонов нет: всё, что нужно экрану,
/// передаётся ему через инициализатор — поэтому любой экран можно поднять
/// в тесте с подставными частями.
@MainActor
@Observable
public final class AppServices {
    public let documents: DocumentRepository
    public let folders: FolderRepository
    public let search: SearchIndex
    public let store: PageStore
    public let thumbnails: ThumbnailLoader
    public let importer: ScanImporter
    public let recognition: TextRecognitionWorker
    public let scanner: VisionKitScanSource
    public let lock: AppLock

    public init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let database = try AppDatabase.onDisk(at: root.appendingPathComponent("leaf.sqlite"))
        let store = try PageStore(root: root.appendingPathComponent("pages", isDirectory: true))

        self.store = store
        self.documents = DocumentRepository(database: database)
        self.folders = FolderRepository(database: database)
        self.search = SearchIndex(database: database)
        self.thumbnails = ThumbnailLoader(store: store)
        self.importer = ScanImporter(store: store)
        self.recognition = TextRecognitionWorker(
            images: store,
            recognizer: TextRecognizer(),
            documents: documents
        )
        self.scanner = VisionKitScanSource()
        self.lock = AppLock()
    }

    /// Хранилище лежит в поддержке приложения, а не в документах: файлы
    /// страниц — внутреннее устройство архива, и показывать их в «Файлах»
    /// значило бы предложить человеку сломать себе архив вручную.
    public static func defaultRoot() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Leaf", isDirectory: true)
    }

    public func makeFitter() -> SizeFitter {
        SizeFitter(source: store)
    }
}
