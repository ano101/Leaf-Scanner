import Foundation

/// Кодирование составных полей страницы в JSON. Обрезка и области замазки —
/// это структуры переменного размера; заводить под них отдельные таблицы
/// значило бы усложнить чтение ради данных, которые всегда читаются целиком.
enum RecordCoding {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<Value: Encodable>(_ value: Value?) throws -> String? {
        guard let value else { return nil }
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from json: String?) throws -> Value? {
        guard let json, json.isEmpty == false else { return nil }
        return try decoder.decode(type, from: Data(json.utf8))
    }
}
