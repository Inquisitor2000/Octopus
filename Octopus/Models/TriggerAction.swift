import AppKit

public enum TargetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case anything     = "Anything"
    case systemAction = "System Action"

    public var id: String { rawValue }
}

public struct TriggerAction: Codable, Hashable, Sendable {
    public var path: String
    public var type: TargetType

    public init(path: String, type: TargetType) {
        self.path = path
        self.type = type
    }
}

public enum SystemAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case missionControl   = "Mission Control"
    case apps             = "Apps"
    case showDesktop      = "Show Desktop"
    case startScreenSaver = "Start Screen Saver"
    case lockScreen       = "Lock Screen"
    case sleepDisplay     = "Put Display to Sleep"
    case controlCenter    = "Control Center"

    public var id: String { rawValue }

    public func perform() {
        switch self {
        case .missionControl:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .apps:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Apps.app"))
        case .showDesktop:
            Self.postKey(code: 103, flags: [])           // F11
        case .startScreenSaver:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
        case .lockScreen:
            Self.postKey(code: 12, flags: [.maskControl, .maskCommand]) // Ctrl+Cmd+Q
        case .sleepDisplay:
            Self.runProcess("/usr/bin/pmset", ["displaysleepnow"])
        case .controlCenter:
            Self.postKey(code: 8, flags: .maskSecondaryFn) // Fn+C (macOS 26 default)
        }
    }

    private static func postKey(code: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private static func runProcess(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[Octopus] System action failed: %@", error.localizedDescription)
        }
    }
}
