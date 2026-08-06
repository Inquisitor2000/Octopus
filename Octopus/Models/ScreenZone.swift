import Foundation

public enum ScreenZone: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeft      = "Top Left"
    case topCenter    = "Top Center"
    case topRight     = "Top Right"
    case rightMiddle  = "Right Middle"
    case bottomRight  = "Bottom Right"
    case bottomCenter = "Bottom Center"
    case bottomLeft   = "Bottom Left"
    case leftMiddle   = "Left Middle"

    public var id: String { rawValue }
}
