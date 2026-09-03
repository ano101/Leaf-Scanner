/// Область, которую нужно уничтожить при выходе файла наружу.
/// Внутри приложения замазка обратима, в экспортированном файле — нет.
public struct RedactionArea: Hashable, Sendable, Codable, Identifiable {
    public let id: Identifier<RedactionArea>
    public let rect: NormalizedRect

    public init(id: Identifier<RedactionArea> = .init(), rect: NormalizedRect) {
        self.id = id
        self.rect = rect
    }
}
