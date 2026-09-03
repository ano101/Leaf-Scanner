import Foundation
import UIKit

/// Единственная точка, из которой готовый файл уходит наружу.
///
/// Отправка, печать и сохранение получают один и тот же файл. Собранный
/// в одном месте выход позволит потом добавить снятие метаданных одной
/// правкой, а не пятью.
public enum ExportDelivery {
    public static func writeTemporaryFile(_ data: Data, name: String) throws -> URL {
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = safeName.isEmpty ? "document" : safeName

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).pdf")

        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    public static func print(_ data: Data, name: String) {
        guard UIPrintInteractionController.canPrint(data) else { return }

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = name

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }
}
