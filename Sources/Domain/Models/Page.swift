public typealias PageID = Identifier<Page>

/// Страница — это исходный кадр плюс намерения человека: как повернуть,
/// где обрезать, что закрыть. Сам кадр не меняется никогда, поэтому любую
/// правку можно отменить, а экспорт всегда идёт от оригинала.
public struct Page: Identifiable, Hashable, Sendable, Codable {
    public let id: PageID
    public var order: Int
    public var rotation: Rotation
    public var filter: PageFilter
    public var crop: NormalizedQuad?
    public var redactions: [RedactionArea]
    public var perceptualHash: UInt64?
    public var recognizedText: String?

    public init(
        id: PageID = .init(),
        order: Int,
        rotation: Rotation = .none,
        filter: PageFilter = .enhanced,
        crop: NormalizedQuad? = nil,
        redactions: [RedactionArea] = [],
        perceptualHash: UInt64? = nil,
        recognizedText: String? = nil
    ) {
        self.id = id
        self.order = order
        self.rotation = rotation
        self.filter = filter
        self.crop = crop
        self.redactions = redactions
        self.perceptualHash = perceptualHash
        self.recognizedText = recognizedText
    }

    public func withOrder(_ newOrder: Int) -> Page {
        var copy = self
        copy.order = newOrder
        return copy
    }
}
