import AppKit
import ApplicationServices
import Combine
import SwiftData
import SwiftUI

@Model
final class ZoneAssignment {
    var zoneRaw: String
    var typeRaw: String?
    var path: String?
    var enabled: Bool
    var dwellOverride: Double?

    init(zone: ScreenZone,
         type: TargetType? = nil,
         path: String? = nil,
         enabled: Bool = false,
         dwellOverride: Double? = nil) {
        self.zoneRaw = zone.rawValue
        self.typeRaw = type?.rawValue
        self.path = path
        self.enabled = enabled
        self.dwellOverride = dwellOverride
    }

    var zone: ScreenZone? { ScreenZone(rawValue: zoneRaw) }

    var action: TriggerAction? {
        guard let typeRaw, let path, !path.isEmpty else { return nil }
        let type = TargetType(rawValue: typeRaw) ?? .anything
        return TriggerAction(path: path, type: type)
    }
}

@MainActor
final class ZoneStore: ObservableObject {
    @Published private(set) var assignments: [ZoneAssignment] = []
    @Published var globalDwell: TimeInterval {
        didSet {
            UserDefaults.standard.set(globalDwell, forKey: Self.dwellKey)
            if engine.isMonitoring { engine.dwellThreshold = effectiveThreshold() }
        }
    }
    @Published var dwellEnabled: Bool {
        didSet {
            UserDefaults.standard.set(dwellEnabled, forKey: Self.dwellEnabledKey)
            if dwellEnabled && globalDwell < 0.5 { globalDwell = 0.5 }
            if engine.isMonitoring { engine.dwellThreshold = effectiveThreshold() }
        }
    }
    @Published var ghostingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(ghostingEnabled, forKey: Self.ghostingEnabledKey)
            engine.triggerCooldown = effectiveCooldown()
        }
    }
    @Published var ghostingSeconds: Int {
        didSet {
            let clamped = min(max(ghostingSeconds, 3), 9)
            if clamped % 2 == 0 {
                ghostingSeconds = min(clamped + 1, 9)
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.ghostingSecondsKey)
            engine.triggerCooldown = effectiveCooldown()
        }
    }
    @Published var monitoringEnabled = false
    @Published var activeZone: ScreenZone?
    @Published var feedbackEffect: TriggerFeedbackEffect {
        didSet {
            UserDefaults.standard.set(feedbackEffect.rawValue, forKey: Self.feedbackEffectKey)
            if feedbackEffect == .none { feedback.hideAll() }
        }
    }
    @Published var feedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(feedbackEnabled, forKey: Self.feedbackEnabledKey)
            if !feedbackEnabled { feedback.hideAll() }
        }
    }
    @Published var feedbackScale: Double {
        didSet {
            UserDefaults.standard.set(feedbackScale, forKey: Self.feedbackScaleKey)
        }
    }
    @Published var soundEffect: TriggerSound {
        didSet {
            UserDefaults.standard.set(soundEffect.rawValue, forKey: Self.soundEffectKey)
        }
    }
    @Published var soundVolume: Double {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: Self.soundVolumeKey)
        }
    }

    let engine = TriggerEngine()
    lazy var feedback = TriggerFeedbackManager(store: self)

    private let container: ModelContainer
    private let context: ModelContext
    private var engineCancellable: AnyCancellable?

    static let dwellKey = "octopus.globalDwell"
    static let dwellEnabledKey = "octopus.dwellEnabled"
    static let monitoringKey = "octopus.monitoringEnabled"
    static let didFirstAutoStartKey = "octopus.didFirstAutoStart"
    static let ghostingEnabledKey = "octopus.ghostingEnabled"
    static let ghostingSecondsKey = "octopus.ghostingSeconds"
    static let feedbackEffectKey = "octopus.feedbackEffect"
    static let feedbackEnabledKey = "octopus.feedbackEnabled"
    static let feedbackScaleKey = "octopus.feedbackScale"
    static let soundEffectKey = "octopus.soundEffect"
    static let soundVolumeKey = "octopus.soundVolume"

    init() {
        let schema = Schema([ZoneAssignment.self])
        do {
            container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration("Octopus", schema: schema)])
        } catch {
            fatalError("[Octopus] Failed to create SwiftData container: \(error)")
        }
        context = container.mainContext

        let saved = UserDefaults.standard.double(forKey: Self.dwellKey)
        globalDwell = saved > 0 ? saved : 0.5
        dwellEnabled = UserDefaults.standard.bool(forKey: Self.dwellEnabledKey)

        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.ghostingEnabledKey) == nil {
            ghostingEnabled = true
            defaults.set(true, forKey: Self.ghostingEnabledKey)
        } else {
            ghostingEnabled = defaults.bool(forKey: Self.ghostingEnabledKey)
        }
        let seconds = defaults.integer(forKey: Self.ghostingSecondsKey)
        ghostingSeconds = [3, 5, 7, 9].contains(seconds) ? seconds : 5
        if let raw = defaults.string(forKey: Self.feedbackEffectKey),
           let effect = TriggerFeedbackEffect(rawValue: raw) {
            feedbackEffect = effect
        } else {
            feedbackEffect = .none
        }
        feedbackEnabled = defaults.object(forKey: Self.feedbackEnabledKey) == nil
            ? false
            : defaults.bool(forKey: Self.feedbackEnabledKey)
        let storedScale = defaults.double(forKey: Self.feedbackScaleKey)
        feedbackScale = storedScale > 0 ? min(max((storedScale * 2).rounded() / 2, 0.5), 2.0) : 1.0
        if let raw = defaults.string(forKey: Self.soundEffectKey),
           let sound = TriggerSound(rawValue: raw) {
            soundEffect = sound
        } else {
            soundEffect = .none
        }
        if defaults.object(forKey: Self.soundVolumeKey) == nil {
            soundVolume = 0.7
        } else {
            soundVolume = min(max(defaults.double(forKey: Self.soundVolumeKey), 0), 1)
        }
        engine.triggerCooldown = effectiveCooldown()

        seedIfNeeded()
        reload()

        engine.onZoneTrigger = { [weak self] zone in
            guard let self else { return }
            guard let action = self.action(for: zone) else { return }
            self.feedback.trigger(zone: zone)
            ActionDispatcher.execute(action: action)
        }
        engineCancellable = engine.$currentActiveZone
            .receive(on: DispatchQueue.main)
            .sink { [weak self] zone in self?.activeZone = zone }
    }

    private func seedIfNeeded() {
        let count = (try? context.fetchCount(FetchDescriptor<ZoneAssignment>())) ?? 0
        guard count == 0 else { return }
        for zone in ScreenZone.allCases {
            context.insert(ZoneAssignment(zone: zone))
        }
        try? context.save()
    }

    func reload() {
        let order = ScreenZone.allCases.map(\.rawValue)
        let fetched = (try? context.fetch(FetchDescriptor<ZoneAssignment>())) ?? []
        assignments = fetched.sorted {
            (order.firstIndex(of: $0.zoneRaw) ?? .max) < (order.firstIndex(of: $1.zoneRaw) ?? .max)
        }

        var changed = false
        for a in assignments {
            let has = a.action != nil
            if a.enabled != has {
                a.enabled = has
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    private func assignment(for zone: ScreenZone) -> ZoneAssignment? {
        assignments.first { $0.zoneRaw == zone.rawValue }
    }

    private func createAssignment(for zone: ScreenZone) -> ZoneAssignment {
        if let existing = assignment(for: zone) { return existing }
        let new = ZoneAssignment(zone: zone)
        context.insert(new)
        reload()
        return new
    }

    func action(for zone: ScreenZone) -> TriggerAction? {
        guard let a = assignment(for: zone), a.enabled else { return nil }
        return a.action
    }

    func setAction(_ action: TriggerAction, for zone: ScreenZone, enabled: Bool = true) {
        let a = createAssignment(for: zone)
        a.typeRaw = action.type.rawValue
        a.path = action.path
        a.enabled = enabled
        saveAndReload()
    }

    func clearAction(for zone: ScreenZone) {
        guard let a = assignment(for: zone) else { return }
        a.typeRaw = nil
        a.path = nil
        a.enabled = false
        saveAndReload()
    }

    private func saveAndReload() {
        try? context.save()
        reload()
    }

    private func effectiveThreshold() -> TimeInterval {
        dwellEnabled ? globalDwell : 0
    }

    private func effectiveCooldown() -> TimeInterval {
        ghostingEnabled ? TimeInterval(ghostingSeconds) : 0
    }

    func toggleMonitoring(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.monitoringKey)
        if on {
            let trusted = Self.checkAccessibilityPermission()
            guard trusted else {
                Self.promptAccessibility()
                monitoringEnabled = false
                return
            }
            engine.dwellThreshold = effectiveThreshold()
            engine.startMonitoring()
            monitoringEnabled = engine.isMonitoring
            if !monitoringEnabled {
                Self.showAlert(title: "Monitoring Failed",
                               message: "The system refused the global mouse monitor even though Accessibility looks granted.\n\nQuit Octopus and reopen it, then re-enable monitoring. If it still fails, toggle Octopus OFF and ON in System Settings → Privacy & Security → Accessibility.")
            }
        } else {
            engine.stopMonitoring()
            monitoringEnabled = false
            feedback.hideAll()
        }
    }

    func autoStartIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.didFirstAutoStartKey) {
            guard Self.checkAccessibilityPermission() else { return }
            defaults.set(true, forKey: Self.didFirstAutoStartKey)
            defaults.set(true, forKey: Self.monitoringKey)
            engine.dwellThreshold = effectiveThreshold()
            engine.startMonitoring()
            monitoringEnabled = engine.isMonitoring
            return
        }
        guard defaults.bool(forKey: Self.monitoringKey) else { return }
        guard Self.checkAccessibilityPermission() else { return }
        engine.dwellThreshold = effectiveThreshold()
        engine.startMonitoring()
        monitoringEnabled = engine.isMonitoring
    }

    static func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    static func checkAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}
