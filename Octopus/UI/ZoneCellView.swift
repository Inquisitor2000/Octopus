import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ZoneCellView: View {
    @ObservedObject var store: ZoneStore
    let zone: ScreenZone
    var onEdit: () -> Void

    @State private var isTargeted = false

    private var assignment: ZoneAssignment? {
        store.assignments.first { $0.zoneRaw == zone.rawValue }
    }

    private var isActive: Bool { store.activeZone == zone }

    private var summary: String {
        guard let assignment, let action = assignment.action else { return "No action" }
        let name = URL(fileURLWithPath: action.path).lastPathComponent
        switch action.type {
        case .anything:
            return "Open: \(name)"
        case .systemAction:
            return "\(action.type.rawValue) · \(name)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(zone.rawValue)
                    .font(.headline)
                Spacer()
                if assignment?.action != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .opacity(0.45)
                }
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Drop an app, file, or script")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted
                      ? Color.accentColor.opacity(0.15)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isActive ? Color.green : Color.gray.opacity(isTargeted ? 0.8 : 0.3),
                    style: StrokeStyle(lineWidth: isActive ? 2 : 1, dash: [4]))
        )
        .onTapGesture { onEdit() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    store.setAction(TriggerAction(path: url.path, type: Self.detectType(for: url)),
                                    for: zone)
                }
            }
            return true
        }
        .help("Assign an action to \(zone.rawValue)")
    }

    private static func detectType(for url: URL) -> TargetType {
        .anything
    }
}

struct CenterCellView: View {
    private static var octopusLogo: NSImage {
        if let image = NSImage(named: "Octo") ?? NSImage(named: "Octo.png") {
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "cursorarrow.motionlines",
                       accessibilityDescription: nil) ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: Self.octopusLogo)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(.primary)
            Text("Active Screen Area")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 96)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
}

enum ZoneGridItem: Identifiable {
    case zone(ScreenZone)
    case center

    var id: String {
        switch self {
        case .zone(let zone): return zone.rawValue
        case .center: return "center"
        }
    }

    static var all: [ZoneGridItem] {
        [
            .zone(.topLeft), .zone(.topCenter), .zone(.topRight),
            .zone(.leftMiddle), .center, .zone(.rightMiddle),
            .zone(.bottomLeft), .zone(.bottomCenter), .zone(.bottomRight),
        ]
    }
}
