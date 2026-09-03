/// Поворот страницы кратен прямому углу: произвольный угол дал бы поля
/// по краям и потерю пикселей, а документу это не нужно.
public enum Rotation: Int, Sendable, Codable, CaseIterable {
    case none = 0
    case right = 90
    case upsideDown = 180
    case left = 270

    public func turnedRight() -> Rotation {
        Rotation(rawValue: (rawValue + 90) % 360) ?? .none
    }

    public func turnedLeft() -> Rotation {
        Rotation(rawValue: (rawValue + 270) % 360) ?? .none
    }

    /// Боковой поворот меняет ширину и высоту местами.
    public var swapsDimensions: Bool {
        self == .right || self == .left
    }
}
