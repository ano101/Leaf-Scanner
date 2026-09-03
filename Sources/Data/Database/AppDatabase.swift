import Foundation
import GRDB

/// Точка доступа к базе. Наружу отдаётся только писатель — слои выше
/// не знают, лежит база на диске или в памяти.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// База в памяти для тестов.
    ///
    /// Создаётся конструктором без пути. Строка «:memory:» здесь не подходит:
    /// драйвер SQLite для Apple трактует её как обычное имя файла, состояние
    /// утекает между тестами, и они начинают зависеть от порядка запуска.
    public static func inMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue(configuration: configuration())
        try migrator.migrate(queue)
        return AppDatabase(writer: queue)
    }

    public static func onDisk(at url: URL) throws -> AppDatabase {
        let pool = try DatabasePool(path: url.path, configuration: configuration())
        try migrator.migrate(pool)
        return AppDatabase(writer: pool)
    }

    private static func configuration() -> Configuration {
        var configuration = Configuration()
        // Каскадное удаление страниц вместе с документом держится на внешних
        // ключах, а SQLite выключает их по умолчанию в каждом соединении.
        configuration.foreignKeysEnabled = true
        return configuration
    }
}
