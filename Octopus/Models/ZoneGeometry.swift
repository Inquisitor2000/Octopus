import AppKit

public enum ZoneGeometry {

    private static let cornerSize: CGFloat = 16.0

    public static func rect(for zone: ScreenZone, in frame: CGRect, margin: CGFloat = 12.0) -> CGRect {
        let w = frame.width
        let h = frame.height

        var topMargin = margin
        if let main = NSScreen.main, main.frame == frame {
            let topInset = frame.maxY - main.visibleFrame.maxY
            if topInset > 0 { topMargin = margin + topInset }
        }

        let c = Self.cornerSize

        switch zone {
        case .topLeft:
            return CGRect(x: frame.minX, y: frame.minY + h - topMargin, width: c, height: topMargin)
        case .topCenter:
            return CGRect(x: frame.minX + w * 0.25, y: frame.minY + h - topMargin, width: w * 0.50, height: topMargin)
        case .topRight:
            return CGRect(x: frame.minX + w - c, y: frame.minY + h - topMargin, width: c, height: topMargin)
        case .rightMiddle:
            return CGRect(x: frame.minX + w - margin, y: frame.minY + h * 0.25, width: margin, height: h * 0.50)
        case .bottomRight:
            return CGRect(x: frame.minX + w - c, y: frame.minY, width: c, height: c)
        case .bottomCenter:
            return CGRect(x: frame.minX + w * 0.25, y: frame.minY, width: w * 0.50, height: margin)
        case .bottomLeft:
            return CGRect(x: frame.minX, y: frame.minY, width: c, height: c)
        case .leftMiddle:
            return CGRect(x: frame.minX, y: frame.minY + h * 0.25, width: margin, height: h * 0.50)
        }
    }

    public static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
