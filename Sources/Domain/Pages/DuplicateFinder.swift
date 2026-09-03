/// «Я это уже сканировал?» — вопрос, который человек задаёт себе сам,
/// разбирая пачку бумаг. Приложение отвечает на него до того, как в архиве
/// появится второй такой же лист.
public enum DuplicateFinder {
    public static func near(
        _ hash: UInt64,
        in pages: [Page],
        maxDistance: Int = PerceptualHash.duplicateThreshold
    ) -> [PageID] {
        pages
            .compactMap { page -> (id: PageID, distance: Int)? in
                // Страница без отпечатка — это ещё не обработанная страница,
                // а не совпадение. Считать её похожей нельзя.
                guard let existing = page.perceptualHash else { return nil }

                let distance = PerceptualHash.distance(hash, existing)
                return distance <= maxDistance ? (page.id, distance) : nil
            }
            .sorted { $0.distance < $1.distance }
            .map(\.id)
    }
}
