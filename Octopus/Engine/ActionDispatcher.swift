import AppKit

public enum ActionDispatcher {
    public static func execute(action: TriggerAction) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard !action.path.isEmpty else { return }

            switch action.type {
            case .anything:
                let ext = URL(fileURLWithPath: action.path).pathExtension.lowercased()
                if ["sh", "zsh"].contains(ext) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = [action.path]
                    do {
                        try process.run()
                        process.waitUntilExit()
                    } catch {
                        NSLog("[Octopus] Script execution failed: %@", error.localizedDescription)
                    }
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: action.path))
                }

            case .systemAction:
                guard let system = SystemAction(rawValue: action.path) else { return }
                system.perform()
            }
        }
    }
}
