/// Ошибки слоя данных. Типизированы, чтобы вызывающий код мог различить
/// «нет такого документа» и «запись в базе испорчена» — это разные разговоры
/// с человеком.
public enum RepositoryError: Error, Equatable, Sendable {
    case documentNotFound(DocumentID)
    case folderNotFound(FolderID)
    case corruptedRecord(table: String, id: String)
    case nothingToMerge
}
