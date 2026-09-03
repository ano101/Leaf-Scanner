import CoreGraphics
import SwiftUI
import VisionKit

/// Съёмка системным сканером документов.
///
/// Apple уже решил поиск границ листа, исправление перспективы, автоспуск
/// и съёмку пачкой. Своя камера дала бы свой оверлей ценой недель работы
/// и худшего качества определения границ на первых версиях.
@MainActor
@Observable
public final class VisionKitScanSource: ScanSource {
    public private(set) var isPresenting = false
    private var continuation: CheckedContinuation<[CGImage], any Error>?

    public init() {}

    public static var isAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    public func scan() async throws -> [CGImage] {
        guard Self.isAvailable else { throw ScanError.cameraUnavailable }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.isPresenting = true
        }
    }

    func finish(with images: [CGImage]) {
        isPresenting = false
        continuation?.resume(returning: images)
        continuation = nil
    }

    func fail(with error: any Error) {
        isPresenting = false
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// Обёртка системного экрана съёмки для SwiftUI.
struct DocumentCamera: UIViewControllerRepresentable {
    let source: VisionKitScanSource

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source)
    }

    /// Системный сканер зовёт делегата на главном потоке, но объявлен
    /// без пометки об этом. `@preconcurrency` сообщает компилятору то,
    /// что документировано, вместо обхода проверок в каждом методе.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let source: VisionKitScanSource

        init(source: VisionKitScanSource) {
            self.source = source
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage }
            source.finish(with: images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            source.fail(with: ScanError.cancelled)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            source.fail(with: error)
        }
    }
}
