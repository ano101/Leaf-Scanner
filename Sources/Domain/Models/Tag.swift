public typealias TagID = Identifier<Tag>

/// Цвет метки хранится ключом справочника, а не значением: палитра
/// меняется без миграции данных.
public struct Tag: Identifiable, Hashable, Sendable {
    public let id: TagID
    public var name: String
    public var colorKey: String

    public init(id: TagID = .init(), name: String, colorKey: String) {
        self.id = id
        self.name = name
        self.colorKey = colorKey
    }
}
