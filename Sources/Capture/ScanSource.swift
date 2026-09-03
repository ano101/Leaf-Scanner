import CoreGraphics
import Foundation

public enum ScanError: Error, Equatable, Sendable {
    case cancelled
    case cameraUnavailable
    case permissionDenied
}

/// Съёмка спрятана за протоколом, чтобы экран документа можно было проверить
/// без камеры, а системный сканер позже заменить своим, не переписывая
/// остальное.
public protocol ScanSource: Sendable {
    @MainActor func scan() async throws -> [CGImage]
}
