import Foundation

/// Идентификатор, привязанный к типу владельца: `PageID` нельзя передать
/// туда, где ждут `DocumentID`, хотя внутри у обоих один и тот же UUID.
/// Тип-параметр нигде не хранится и служит только для проверки компилятором.
public struct Identifier<Subject>: Hashable, Sendable, Codable {
    public let raw: UUID

    public init(_ raw: UUID = UUID()) {
        self.raw = raw
    }
}

extension Identifier: CustomStringConvertible {
    public var description: String { raw.uuidString }
}
