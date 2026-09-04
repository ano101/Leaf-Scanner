/// Требования учреждений к загружаемым файлам. Люди ищут эти цифры в интернете
/// и подгоняют вручную — здесь они лежат готовыми.
///
/// Справочник, а не перечислимый тип: от значения не ветвится ни одна строка
/// кода, набор расширяется без изменения логики подбора.
public struct ExportPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let limitBytes: Int?
    public let look: PageLook
    public let maxLongSide: Int?

    public init(id: String, limitBytes: Int?, look: PageLook, maxLongSide: Int?) {
        self.id = id
        self.limitBytes = limitBytes
        self.look = look
        self.maxLongSide = maxLongSide
    }

    public var titleKey: String { "export.preset.\(id)" }

    public static let customKey = "custom"

    private static let megabyte = 1_048_576

    public static let all: [ExportPreset] = [
        ExportPreset(id: "gosuslugi", limitBytes: 5 * megabyte, look: .color, maxLongSide: 2400),
        ExportPreset(id: "email", limitBytes: 10 * megabyte, look: .color, maxLongSide: nil),
        ExportPreset(id: "bank", limitBytes: 2 * megabyte, look: .gray, maxLongSide: 2000),
        ExportPreset(id: "visa", limitBytes: megabyte, look: .color, maxLongSide: 1600),
        ExportPreset(id: customKey, limitBytes: nil, look: .color, maxLongSide: nil),
    ]
}
