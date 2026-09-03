# Leaf — сканер документов. План реализации

> **Для исполнителя:** обязательный под-навык — `superpowers:executing-plans`
> или `superpowers:subagent-driven-development`. Шаги отмечаются чекбоксами.

**Цель:** нативное офлайн-приложение для iOS, которое сканирует документы,
хранит их постранично и отдаёт наружу файлом заданного веса.

**Архитектура:** страницы хранятся отдельными файлами плюс метаданные в SQLite;
PDF собирается только в момент экспорта. Слои `Domain → Data/Imaging/Recognition
→ Presentation`, `Domain` без внешних зависимостей и потому тестируется без диска.

**Опоры:** Swift 6.2.4 строгая конкурентность, iOS 26.0, Xcode 26.3,
GRDB 7.11.1, XcodeGen, SwiftUI, VisionKit, Vision, PDFKit, Core Image.

**Спека:** `docs/superpowers/specs/2026-09-04-leaf-scanner-design.md`

## Общие ограничения

- `swift-tools` и цели собираются под iOS 26.0, не ниже.
- Единственная сторонняя зависимость — GRDB 7.11.1, версия закреплена точно.
- Ни одной строки интерфейса в коде: только ключи локализации. Языки ru, en.
- Идентификаторы на английском, комментарии и сообщения коммитов на русском.
- Явные типы у всех публичных объявлений; `Any` и неявные опционалы запрещены.
- Пустой `catch` запрещён; ошибки типизированы.
- Во `View` нет логики и обращений к репозиториям; зависимости — через инициализатор.
- Сначала падающий тест, потом код. Коммит после каждой задачи.
- Симулятор — только через панель (`attach`, `launch`, `screenshot`, `tap`),
  свои симуляторы не создаются, `-derivedDataPath` собственный: `./DerivedData`.
- Тест не роняет процесс: сначала утверждение о количестве, потом об элементе.

## Структура файлов

```
project.yml                          описание проекта для XcodeGen
Sources/App/                         точка входа, настройки, сборка зависимостей
Sources/Domain/Models/               Document, Page, Folder, Tag — чистые данные
Sources/Domain/Pages/                порядок страниц, чередование сторон
Sources/Domain/Export/               целевой вес, пресеты, план сжатия
Sources/Domain/Redaction/            области замазки
Sources/Data/Database/               GRDB, миграции
Sources/Data/Records/                записи таблиц
Sources/Data/Repositories/           доступ к документам, папкам, тегам
Sources/Data/Search/                 индекс FTS5
Sources/Data/Files/                  файлы страниц и миниатюры
Sources/Imaging/                     фильтры, рендер страницы, сборка PDF, подгон веса
Sources/Recognition/                 распознавание текста, поиск ПДн, перцептивный хеш
Sources/Capture/                     протокол съёмки и реализация на VisionKit
Sources/Presentation/Archive/        экран архива
Sources/Presentation/Document/       экран документа
Sources/Presentation/Export/         экран экспорта
Sources/Presentation/Common/         переиспользуемые элементы
Sources/Resources/                   Localizable.xcstrings, ассеты
Tests/DomainTests/                   правила без диска
Tests/DataTests/                     база, миграции, поиск
Tests/ImagingTests/                  рендер, PDF, замазка, подгон веса
Tests/RecognitionTests/              распознавание, ПДн, хеш
```

---

### Задача 1: каркас проекта и первая зелёная сборка

**Файлы:**
- Создать: `project.yml`, `Sources/App/LeafApp.swift`, `Sources/App/AppInfo.swift`
- Создать: `Sources/Resources/Info.plist`, `Sources/Resources/Localizable.xcstrings`
- Создать: `Tests/DomainTests/AppInfoTests.swift`
- Создать: `Makefile`

**Интерфейсы:**
- Отдаёт: `enum AppInfo { static let name: String; static let bundleIdentifier: String }`

- [ ] **Шаг 1: установить XcodeGen**

```bash
brew install xcodegen
```

- [ ] **Шаг 2: написать падающий тест**

`Tests/DomainTests/AppInfoTests.swift`:

```swift
import XCTest
@testable import Leaf

final class AppInfoTests: XCTestCase {
    func testИмяПриложенияЗадано() {
        XCTAssertFalse(AppInfo.name.isEmpty)
    }
}
```

- [ ] **Шаг 3: описать проект в `project.yml`**

Цели: `Leaf` (приложение, iOS 26.0) и `LeafTests`. Обязательно
`CODE_SIGNING_ALLOWED: YES` и `CODE_SIGN_IDENTITY: "-"`, иначе локальный запуск
не подписывается. Зависимость GRDB через `packages:` с `exactVersion: 7.11.1`.

- [ ] **Шаг 4: убедиться, что тест падает**

Run: `make test`
Ожидается: ошибка компиляции «cannot find 'AppInfo' in scope».

- [ ] **Шаг 5: минимальная реализация**

`Sources/App/AppInfo.swift`:

```swift
public enum AppInfo {
    public static let name = "Leaf"
    public static let bundleIdentifier = "ru.kotliar.leaf"
}
```

- [ ] **Шаг 6: тест зелёный, приложение собирается**

Run: `make test && make build`

- [ ] **Шаг 7: коммит**

```bash
git add project.yml Makefile Sources Tests
git commit -m "Каркас проекта: цели, зависимости, первая зелёная сборка"
```

---

### Задача 2: модели предметной области и порядок страниц

**Файлы:**
- Создать: `Sources/Domain/Models/{Document,Page,Folder,Tag}.swift`
- Создать: `Sources/Domain/Pages/PageOrdering.swift`
- Создать: `Tests/DomainTests/PageOrderingTests.swift`

**Интерфейсы:**
- Отдаёт:
  - `struct PageID: Hashable, Sendable` (обёртка над `UUID`)
  - `struct Page: Identifiable, Equatable, Sendable` с полями
    `id: PageID`, `order: Int`, `rotation: Rotation`, `filter: PageFilter`,
    `crop: NormalizedQuad?`, `redactions: [RedactionArea]`, `perceptualHash: UInt64?`
  - `enum Rotation: Int, Sendable { case none = 0, right = 90, upsideDown = 180, left = 270 }`
    с методом `func turnedRight() -> Rotation`
  - `enum PageOrdering { static func move(_ pages: [Page], from: Int, to: Int) -> [Page]
    static func renumbered(_ pages: [Page]) -> [Page] }`

- [ ] **Шаг 1: падающие тесты порядка**

```swift
func testПереносСтраницыВперёдСохраняетОстальныеПодряд() {
    let pages = makePages(count: 4)
    let moved = PageOrdering.move(pages, from: 0, to: 2)
    XCTAssertEqual(moved.count, 4)
    XCTAssertEqual(moved.map(\.order), [0, 1, 2, 3])
    XCTAssertEqual(moved[2].id, pages[0].id)
}

func testПоворотНаправоЧетыреРазаВозвращаетИсходный() {
    var r = Rotation.none
    for _ in 0..<4 { r = r.turnedRight() }
    XCTAssertEqual(r, .none)
}
```

- [ ] **Шаг 2: запустить, убедиться в падении.** `make test`
- [ ] **Шаг 3: реализовать модели и `PageOrdering`.**
- [ ] **Шаг 4: тесты зелёные.** `make test`
- [ ] **Шаг 5: мутация** — сломать `renumbered`, убедиться, что тест краснеет, вернуть.
- [ ] **Шаг 6: коммит** «Модели документов и порядок страниц».

---

### Задача 3: чередование двусторонней стопки

**Файлы:**
- Создать: `Sources/Domain/Pages/DuplexInterleaver.swift`
- Создать: `Tests/DomainTests/DuplexInterleaverTests.swift`

**Интерфейсы:**
- Отдаёт: `enum DuplexInterleaver { static func interleave(fronts: [Page], backs: [Page]) -> [Page] }`
  Обороты приходят в обратном порядке (пачку переворачивают целиком).

- [ ] **Шаг 1: падающие тесты**

```swift
func testОборотыИдутВОбратномПорядкеИЧередуются() {
    let fronts = makePages(count: 3, prefix: "f")   // f0 f1 f2
    let backs = makePages(count: 3, prefix: "b")    // снято как b2 b1 b0
    let result = DuplexInterleaver.interleave(fronts: fronts, backs: backs)
    XCTAssertEqual(result.count, 6)
    XCTAssertEqual(result.map(\.id), [fronts[0].id, backs[2].id,
                                      fronts[1].id, backs[1].id,
                                      fronts[2].id, backs[0].id])
}

func testЛишниеЛицевыеОстаютсяБезОборотов() {
    let result = DuplexInterleaver.interleave(fronts: makePages(count: 3),
                                              backs: makePages(count: 1, prefix: "b"))
    XCTAssertEqual(result.count, 4)
}

func testПустыеОборотыДаютТолькоЛицевые() {
    let fronts = makePages(count: 2)
    XCTAssertEqual(DuplexInterleaver.interleave(fronts: fronts, backs: []).count, 2)
}
```

- [ ] **Шаг 2: падение.** **Шаг 3: реализация.** **Шаг 4: зелёные.**
- [ ] **Шаг 5: мутация** — убрать разворот оборотов, тест обязан покраснеть.
- [ ] **Шаг 6: коммит** «Чередование сторон двусторонней стопки».

---

### Задача 4: целевой вес — план сжатия и пресеты

**Файлы:**
- Создать: `Sources/Domain/Export/ExportPlan.swift`
- Создать: `Sources/Domain/Export/ExportPreset.swift`
- Создать: `Sources/Domain/Export/SizeSearch.swift`
- Создать: `Tests/DomainTests/SizeSearchTests.swift`

**Интерфейсы:**
- Отдаёт:
  - `struct ExportPlan: Equatable, Sendable { var quality: Double; var scale: Double; var colorMode: ColorMode }`
  - `enum ColorMode: String, CaseIterable, Sendable { case color, gray, blackAndWhite }`
  - `struct ExportPreset: Identifiable, Sendable { let id: String; let limitBytes: Int?;
    let colorMode: ColorMode; let maxLongSide: Int? }` и `static let all: [ExportPreset]`
  - `enum SizeSearch { static func fit(limitBytes: Int, colorMode: ColorMode,
    measure: (ExportPlan) -> Int) -> SizeSearchResult }`
  - `enum SizeSearchResult: Equatable, Sendable { case fitted(ExportPlan, bytes: Int)
    case needsWeakerColor(suggestion: ColorMode) case impossible(bestBytes: Int) }`

`measure` — замыкание, возвращающее вес для плана. Домен не знает, как считается
вес, поэтому поиск тестируется без единого файла.

- [ ] **Шаг 1: падающие тесты**

```swift
func testПоискНаходитПланВложившийсяВЛимит() {
    // вес линейно зависит от качества: 10 МБ при 1.0
    let measure: (ExportPlan) -> Int = { Int(10_000_000 * $0.quality * $0.scale) }
    let result = SizeSearch.fit(limitBytes: 1_000_000, colorMode: .color, measure: measure)
    guard case let .fitted(_, bytes) = result else { return XCTFail("ожидался fitted, пришло \(result)") }
    XCTAssertLessThanOrEqual(bytes, 1_000_000)
}

func testНедостижимыйЛимитВЦветеПредлагаетСерый() {
    let measure: (ExportPlan) -> Int = { _ in 9_000_000 }
    let result = SizeSearch.fit(limitBytes: 500_000, colorMode: .color, measure: measure)
    XCTAssertEqual(result, .needsWeakerColor(suggestion: .gray))
}

func testНедостижимыйЛимитВЧёрноБеломНеПредлагаетНичего() {
    let measure: (ExportPlan) -> Int = { _ in 9_000_000 }
    let result = SizeSearch.fit(limitBytes: 500_000, colorMode: .blackAndWhite, measure: measure)
    XCTAssertEqual(result, .impossible(bestBytes: 9_000_000))
}

func testПоискНеДелаетБольшеШестиИзмерений() {
    var calls = 0
    _ = SizeSearch.fit(limitBytes: 1_000_000, colorMode: .color) { plan in
        calls += 1
        return Int(10_000_000 * plan.quality * plan.scale)
    }
    XCTAssertLessThanOrEqual(calls, 6)
}
```

- [ ] **Шаг 2: падение.** **Шаг 3: реализация двоичного поиска.** **Шаг 4: зелёные.**
- [ ] **Шаг 5: мутация** — снять ограничение числа шагов, убедиться, что тест на шесть измерений краснеет.
- [ ] **Шаг 6: коммит** «Подбор параметров под целевой вес файла и пресеты».

---

### Задача 5: база данных, миграции, репозиторий документов

**Файлы:**
- Создать: `Sources/Data/Database/AppDatabase.swift`, `Sources/Data/Database/Migrations.swift`
- Создать: `Sources/Data/Records/{DocumentRecord,PageRecord,FolderRecord,TagRecord}.swift`
- Создать: `Sources/Data/Repositories/DocumentRepository.swift`
- Создать: `Tests/DataTests/DocumentRepositoryTests.swift`

**Интерфейсы:**
- Отдаёт:
  - `struct AppDatabase: Sendable { static func inMemory() throws -> AppDatabase;
    static func onDisk(at url: URL) throws -> AppDatabase; let writer: any DatabaseWriter }`
  - `protocol DocumentRepositoryProtocol: Sendable` с методами
    `func save(_ document: Document) async throws`,
    `func all(inFolder: FolderID?) async throws -> [Document]`,
    `func delete(_ id: DocumentID) async throws`,
    `func merge(_ ids: [DocumentID], into name: String) async throws -> Document`

**Ловушка:** база «в памяти» на iOS не создаётся строкой `:memory:` — только
конструктором `DatabaseQueue()` без пути. Строка трактуется как имя файла,
и состояние утекает между тестами.

- [ ] **Шаг 1: падающие тесты**

```swift
func testСохранённыйДокументЧитаетсяОбратно() async throws {
    let repo = DocumentRepository(database: try AppDatabase.inMemory())
    let doc = Document(name: "Договор", pages: makePages(count: 2))
    try await repo.save(doc)
    let all = try await repo.all(inFolder: nil)
    XCTAssertEqual(all.count, 1)
    XCTAssertEqual(all.first?.pages.count, 2)
}

func testСлияниеДвухДокументовСохраняетПорядокСтраниц() async throws { ... }

func testОткатТранзакцииПриОшибкеНеОставляетЧастичныхДанных() async throws { ... }
```

- [ ] **Шаг 2–4: падение → миграция v1 → зелёные.**
- [ ] **Шаг 5: мутация** — убрать транзакцию в `merge`, тест отката обязан покраснеть.
- [ ] **Шаг 6: коммит** «Хранилище документов на SQLite и слияние».

---

### Задача 6: полнотекстовый поиск на FTS5

**Файлы:**
- Создать: `Sources/Data/Search/SearchIndex.swift`
- Изменить: `Sources/Data/Database/Migrations.swift` (миграция v2)
- Создать: `Tests/DataTests/SearchIndexTests.swift`

**Интерфейсы:**
- Отдаёт: `protocol SearchIndexProtocol: Sendable { func index(pageID: PageID,
  documentID: DocumentID, text: String) async throws;
  func search(_ query: String, limit: Int) async throws -> [SearchHit] }`
- `struct SearchHit: Equatable, Sendable { let documentID: DocumentID;
  let pageID: PageID; let snippet: String }`

- [ ] **Шаг 1: падающие тесты** — поиск находит слово по части, отдаёт фрагмент
  с подсветкой, удаление документа убирает его из индекса, поиск по пустой
  строке возвращает пусто и не бросает.
- [ ] **Шаг 2–4: падение → таблица FTS5 с триггерами → зелёные.**
- [ ] **Шаг 5: мутация** — удалить триггер удаления, тест на удаление краснеет.
- [ ] **Шаг 6: коммит** «Полнотекстовый поиск по распознанному тексту».

---

### Задача 7: файловое хранилище страниц и миниатюры

**Файлы:**
- Создать: `Sources/Data/Files/PageStore.swift`
- Создать: `Tests/DataTests/PageStoreTests.swift`

**Интерфейсы:**
- Отдаёт: `protocol PageStoreProtocol: Sendable { func storeOriginal(_ image: CGImage,
  for id: PageID) async throws -> URL; func original(for id: PageID) async throws -> CGImage;
  func thumbnail(for id: PageID, maxSide: Int) async throws -> CGImage;
  func remove(_ id: PageID) async throws }`

Миниатюра готовится при сохранении и кладётся отдельным файлом — список
не должен открывать оригиналы. Защита данных файлов — `.completeUnlessOpen`.

- [ ] **Шаги 1–4:** тест «миниатюра не длиннее заданной стороны», тест «удаление
  убирает оба файла», тест «повторное чтение не пересчитывает миниатюру».
- [ ] **Шаг 5: коммит** «Хранилище страниц и миниатюр на диске».

---

### Задача 8: рендер страницы — поворот, обрезка, фильтр

**Файлы:**
- Создать: `Sources/Imaging/PageRenderer.swift`, `Sources/Imaging/ImageFilters.swift`
- Создать: `Tests/ImagingTests/PageRendererTests.swift`

**Интерфейсы:**
- Отдаёт: `struct PageRenderer: Sendable { func render(_ image: CGImage,
  page: Page, colorMode: ColorMode, scale: Double) throws -> CGImage }`

- [ ] **Шаги 1–4:** тест «поворот на 90 меняет ширину и высоту местами», тест
  «обрезка уменьшает размер согласно доле», тест «чёрно-белый режим оставляет
  не больше двух уровней яркости».
- [ ] **Шаг 5: коммит** «Рендер страницы: поворот, обрезка, цветовые режимы».

---

### Задача 9: сборка PDF с текстовым слоем

**Файлы:**
- Создать: `Sources/Imaging/PDFBuilder.swift`
- Создать: `Tests/ImagingTests/PDFBuilderTests.swift`

**Интерфейсы:**
- Отдаёт: `struct PDFBuilder: Sendable { func build(pages: [RenderedPage],
  password: String?) throws -> Data }`
- `struct RenderedPage: Sendable { let image: CGImage; let text: [RecognizedLine] }`
- `struct RecognizedLine: Sendable { let text: String; let box: CGRect }` — координаты нормализованы.

- [ ] **Шаги 1–4:** тест «в собранном PDF столько же страниц, сколько передано»,
  тест «текст извлекается из PDF обратно», тест «PDF с паролем не открывается
  без него и открывается с ним».
- [ ] **Шаг 5: коммит** «Сборка PDF с невидимым текстовым слоем и паролем».

---

### Задача 10: безвозвратная замазка

**Файлы:**
- Создать: `Sources/Domain/Redaction/RedactionArea.swift`
- Изменить: `Sources/Imaging/PageRenderer.swift`, `Sources/Imaging/PDFBuilder.swift`
- Создать: `Tests/ImagingTests/RedactionTests.swift`

**Интерфейсы:**
- Отдаёт: `struct RedactionArea: Equatable, Sendable { let rect: CGRect }` — нормализованные координаты.
- Изменяет `PDFBuilder.build`: строки, чьи рамки пересекаются с областями
  замазки, в текстовый слой не попадают.

- [ ] **Шаг 1: падающий тест — главный тест приватности**

```swift
func testЗамазанныйТекстОтсутствуетВСобранномPDF() throws {
    let page = RenderedPage(image: imageWithBlackBox(at: secretRect),
                            text: [RecognizedLine(text: "4276 1300 0000 1111", box: secretRect),
                                   RecognizedLine(text: "Договор", box: safeRect)])
    let data = try PDFBuilder().build(pages: [page], password: nil)
    let extracted = try extractText(from: data)
    XCTAssertFalse(extracted.contains("4276"))
    XCTAssertTrue(extracted.contains("Договор"))
}

func testЗамазанныеПикселиОдноцветны() throws {
    let rendered = try PageRenderer().render(sample, page: pageWithRedaction,
                                             colorMode: .color, scale: 1.0)
    XCTAssertEqual(distinctColors(in: rendered, rect: secretRect).count, 1)
}
```

- [ ] **Шаг 2: падение.** **Шаг 3: реализация.** **Шаг 4: зелёные.**
- [ ] **Шаг 5: мутация обязательна** — снять фильтрацию строк в `PDFBuilder`,
  тест на отсутствие текста обязан покраснеть. Без этой проверки тест
  способен проходить, ничего не проверяя.
- [ ] **Шаг 6: коммит** «Безвозвратная замазка: уничтожение пикселей и текстового слоя».

---

### Задача 11: подгон под целевой вес на настоящих данных

**Файлы:**
- Создать: `Sources/Imaging/SizeFitter.swift`
- Создать: `Tests/ImagingTests/SizeFitterTests.swift`

**Интерфейсы:**
- Отдаёт: `struct SizeFitter: Sendable { func fit(pages: [Page], limitBytes: Int,
  colorMode: ColorMode) async throws -> SizeSearchResult }`

Измерение веса выполняется на уменьшенных копиях; в полном разрешении
рендерится только выбранный план, один раз.

- [ ] **Шаги 1–4:** тест «результат не превышает лимит», тест «полный рендер
  вызывается ровно один раз» (через счётчик в подставном рендерере), тест
  «самая тяжёлая страница определяется верно».
- [ ] **Шаг 5: коммит** «Подгон файла под заданный вес на пробных копиях».

---

### Задача 12: распознавание текста

**Файлы:**
- Создать: `Sources/Recognition/TextRecognizer.swift`
- Создать: `Tests/RecognitionTests/TextRecognizerTests.swift`, фикстура-изображение

**Интерфейсы:**
- Отдаёт: `protocol TextRecognizerProtocol: Sendable { func recognize(_ image: CGImage)
  async throws -> [RecognizedLine] }`, реализация на `RecognizeDocumentsRequest` (iOS 26).

- [ ] **Шаги 1–4:** тест «на изображении с известной надписью она распознана»,
  тест «на пустом изображении возвращается пустой массив без ошибки».
- [ ] **Шаг 5: коммит** «Распознавание текста через Vision».

---

### Задача 13: поиск персональных данных

**Файлы:**
- Создать: `Sources/Recognition/SensitiveDataDetector.swift`
- Создать: `Tests/RecognitionTests/SensitiveDataDetectorTests.swift`

**Интерфейсы:**
- Отдаёт: `enum SensitiveKind: String, Sendable { case cardNumber, passport, taxID, phone }`
- `struct SensitiveMatch: Equatable, Sendable { let kind: SensitiveKind; let box: CGRect }`
- `struct SensitiveDataDetector: Sendable { func detect(in lines: [RecognizedLine]) -> [SensitiveMatch] }`

- [ ] **Шаги 1–4:** тест «номер карты с пробелами найден», тест «номер карты,
  не проходящий проверку Луна, не считается картой», тест «обычное число из
  шестнадцати цифр в тексте договора не даёт ложного срабатывания».
- [ ] **Шаг 5: коммит** «Поиск персональных данных в распознанном тексте».

---

### Задача 14: перцептивный хеш и дубликаты

**Файлы:**
- Создать: `Sources/Recognition/PerceptualHash.swift`
- Создать: `Sources/Domain/Pages/DuplicateFinder.swift`
- Создать: `Tests/RecognitionTests/PerceptualHashTests.swift`

**Интерфейсы:**
- Отдаёт: `enum PerceptualHash { static func hash(_ image: CGImage) -> UInt64 }`
- `enum DuplicateFinder { static func near(_ hash: UInt64, in pages: [Page],
  maxDistance: Int) -> [PageID] }`

- [ ] **Шаги 1–4:** тест «то же изображение даёт тот же хеш», тест «то же
  изображение с изменённой яркостью остаётся в пределах порога», тест
  «непохожее изображение выходит за порог».
- [ ] **Шаг 5: коммит** «Перцептивный хеш и обнаружение повторных сканов».

---

### Задача 15: слой съёмки

**Файлы:**
- Создать: `Sources/Capture/ScanSource.swift`, `Sources/Capture/VisionKitScanSource.swift`
- Создать: `Tests/DomainTests/ScanSourceTests.swift` (подставная реализация)

**Интерфейсы:**
- Отдаёт: `protocol ScanSource: Sendable { func scan() async throws -> [CGImage] }`
- `enum ScanError: Error, Sendable { case cancelled, cameraUnavailable, permissionDenied }`

- [ ] **Шаги 1–4:** тест «отмена съёмки не создаёт документ», тест «две пачки
  собираются в двусторонний документ через `DuplexInterleaver`».
- [ ] **Шаг 5: коммит** «Слой съёмки за протоколом и реализация на VisionKit».

---

### Задача 16: экран архива

**Файлы:**
- Создать: `Sources/Presentation/Archive/{ArchiveView,ArchiveModel,DocumentCell,FolderCell}.swift`
- Создать: `Tests/DomainTests/ArchiveModelTests.swift`

- [ ] **Шаги 1–4:** тест «поиск фильтрует список», тест «документы группируются
  по дате с заголовками», тест «удаление убирает из списка».
- Вёрстка: переносов по слогам нет, число строк задано явно, иерархия размером.
- [ ] **Шаг 5: коммит** «Экран архива: папки, документы, поиск».

---

### Задача 17: экран документа

**Файлы:**
- Создать: `Sources/Presentation/Document/{DocumentView,DocumentModel,PageThumbnail}.swift`
- Создать: `Tests/DomainTests/DocumentModelTests.swift`

- [ ] **Шаги 1–4:** тест «поворот меняет угол страницы», тест «перетаскивание
  меняет порядок», тест «разделение создаёт два документа».
- [ ] **Шаг 5: коммит** «Экран документа: страницы, поворот, порядок, разделение».

---

### Задача 18: экран экспорта

**Файлы:**
- Создать: `Sources/Presentation/Export/{ExportView,ExportModel,PresetPicker}.swift`
- Создать: `Tests/DomainTests/ExportModelTests.swift`

- [ ] **Шаги 1–4:** тест «выбор пресета подставляет лимит», тест «недостижимый
  лимит показывает предложение сменить цветовой режим, а не тупик», тест
  «итоговый размер показан до сохранения».
- [ ] **Шаг 5: коммит** «Экран экспорта: вес, пресеты, предпросмотр размера».

---

### Задача 19: защита доступа

**Файлы:**
- Создать: `Sources/App/AppLock.swift`, `Sources/Presentation/Common/LockView.swift`
- Создать: `Tests/DomainTests/AppLockTests.swift`

- [ ] **Шаги 1–4:** тест «до успешной проверки архив не отдаёт документы», тест
  «возврат из фона снова запирает», тест «отказ оставляет экран запертым, а не пустым».
- [ ] **Шаг 5: мутация** — убрать запирание при уходе в фон, тест краснеет.
- [ ] **Шаг 6: коммит** «Блокировка входа по Face ID».

---

### Задача 20: выход наружу — печать, «Поделиться», «Файлы»

**Файлы:**
- Создать: `Sources/Presentation/Export/ExportDelivery.swift`

Единственная точка сборки итогового файла — чтобы снятие метаданных
(отложенная идея 7) добавлялось потом одной правкой.

- [ ] **Шаги 1–4:** тест «все три пути получают один и тот же файл», живая
  проверка печати и листа «Поделиться» на симуляторе.
- [ ] **Шаг 5: коммит** «Печать, отправка и сохранение в Файлы из одной точки».

---

### Задача 21: локализация

**Файлы:**
- Изменить: `Sources/Resources/Localizable.xcstrings`
- Создать: `Tests/DomainTests/LocalizationTests.swift`

- [ ] **Шаги 1–4:** тест «в исходниках нет строковых литералов интерфейса»
  (проверка по каталогу), тест «каждый ключ имеет перевод на ru и en».
- [ ] **Шаг 5: коммит** «Локализация ru и en, проверка отсутствия литералов».

---

### Задача 22: живая проверка на устройстве

- [ ] Собрать: `xcodebuild build -scheme Leaf -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ./DerivedData`
- [ ] `attach` панели, `launch` собранного `.app`.
- [ ] Пройти сценарий целиком: съёмка, поворот, замазка, экспорт под 1 МБ,
  «Поделиться», печать, поиск по тексту.
- [ ] Снимки экранов приложить к отчёту. Проверить длинное название,
  максимальный системный шрифт, тёмную тему.
- [ ] Коммит «Живая проверка сценария на устройстве».

---

### Задача 23: замеры скорости

**Файлы:**
- Создать: `Tests/PerformanceTests/ArchivePerformanceTests.swift`

Цели из спеки должны проверяться замером, а не ощущением.

- [ ] **Шаг 1:** тест `testАрхивИзТысячиДокументовОткрываетсяБыстрее100мс` —
  наполнить базу тысячей документов, замерить `measure` на выдаче списка.
- [ ] **Шаг 2:** тест `testПоискПоТекстуОтвечаетБыстрее50мс` на том же наборе.
- [ ] **Шаг 3:** тест `testМиниатюраБерётсяИзФайлаАНеИзОригинала` — счётчик
  открытий оригиналов при показе списка обязан остаться нулём.
- [ ] **Шаг 4: коммит** «Замеры скорости архива и поиска».

## Известные пробелы плана

- Ручная обрезка углов после съёмки: логика в задаче 8, экран — часть задачи 17.
- Экраны отказов (нет доступа к камере, кончилось место): часть задач 15 и 16.
- Папки и теги: хранение в задаче 5, интерфейс в задаче 16.
