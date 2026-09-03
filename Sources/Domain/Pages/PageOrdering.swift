/// Порядок страниц — единственный источник правды о том, как документ
/// выглядит при сборке. Все перестановки проходят здесь, чтобы нумерация
/// не расходилась со списком.
public enum PageOrdering {
    public static func sorted(_ pages: [Page]) -> [Page] {
        pages.sorted { $0.order < $1.order }
    }

    /// Расставляет номера подряд с нуля, сохраняя текущий порядок в массиве.
    public static func renumbered(_ pages: [Page]) -> [Page] {
        pages.enumerated().map { index, page in page.withOrder(index) }
    }

    /// Индексы вне списка возвращают список нетронутым: перестановка,
    /// пришедшая из интерфейса, не должна ронять приложение.
    public static func move(_ pages: [Page], from source: Int, to destination: Int) -> [Page] {
        guard pages.indices.contains(source), pages.indices.contains(destination) else {
            return pages
        }
        guard source != destination else { return pages }

        var reordered = pages
        let page = reordered.remove(at: source)
        reordered.insert(page, at: destination)

        return renumbered(reordered)
    }
}
