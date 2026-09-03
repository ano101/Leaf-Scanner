import Testing
@testable import Leaf

@Suite("Сведения о приложении")
struct AppInfoTests {
    @Test("имя приложения задано и не пустое")
    func nameIsNotEmpty() {
        #expect(AppInfo.name.isEmpty == false)
    }

    @Test("идентификатор пакета совпадает с настройками сборки")
    func bundleIdentifierMatchesBuildSettings() {
        #expect(AppInfo.bundleIdentifier == "ru.kotliar.leaf")
    }
}
