import AppKit
import Combine

@MainActor
public final class TriggerEngine: ObservableObject {
    @Published public var currentActiveZone: ScreenZone?
    @Published public var isMonitoring = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dwellTimer: Timer?
    private var activeZone: ScreenZone?
    private var pendingZone: ScreenZone?
    private var watchdogTimer: Timer?
    private var lastEvaluation = Date.distantPast

    public var dwellThreshold: TimeInterval = 0.35
    public var dwellOverride: ((ScreenZone) -> TimeInterval?)?
    public var onZoneTrigger: ((ScreenZone) -> Void)?
    public var onDwellProgress: ((ScreenZone, Double) -> Void)?

    public var triggerCooldown: TimeInterval = 8
    private var lastTriggerDate: [ScreenZone: Date] = [:]

    public init() {}

    public func startMonitoring() {
        stopMonitoring()

        guard createTap() else {
            isMonitoring = false
            return
        }

        isMonitoring = true

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isMonitoring, let tap = self.eventTap else { return }
                if !CFMachPortIsValid(tap) {
                    NSLog("[Octopus] event tap invalid, restarting")
                    self.restartTap()
                } else if !CGEvent.tapIsEnabled(tap: tap) {
                    // Port can stay valid while macOS has disabled the tap
                    // (timeout/user-input disable). Recover, or rebuild.
                    NSLog("[Octopus] event tap disabled, re-enabling")
                    CGEvent.tapEnable(tap: tap, enable: true)
                    if !CGEvent.tapIsEnabled(tap: tap) {
                        NSLog("[Octopus] event tap could not be re-enabled, restarting")
                        self.restartTap()
                    }
                }
            }
        }
    }

    public func stopMonitoring() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        teardownTap()
        resetDwell()
        isMonitoring = false
    }

    private func createTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<TriggerEngine>.fromOpaque(refcon).takeUnretainedValue()

            // macOS silently disables the tap when the callback is slow
            // (heavy load, wake from sleep) and delivers these final events.
            // Re-enable immediately or the tap stays dead until recreated.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task { @MainActor in
                    engine.recoverTap()
                }
                return Unmanaged.passUnretained(event)
            }

            let location = NSEvent.mouseLocation
            Task { @MainActor in
                engine.evaluateMousePosition(location)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func restartTap() {
        teardownTap()
        if !createTap() {
            isMonitoring = false
        }
    }

    private func recoverTap() {
        guard isMonitoring, let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        if !CGEvent.tapIsEnabled(tap: tap) {
            NSLog("[Octopus] event tap could not be re-enabled, restarting")
            restartTap()
        }
    }

    private func evaluateMousePosition(_ point: NSPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastEvaluation) >= 0.01 else { return }
        lastEvaluation = now

        guard let screen = ZoneGeometry.screen(containing: point) else {
            clearActive()
            return
        }

        let matchingZone = ScreenZone.allCases.first { zone in
            ZoneGeometry.rect(for: zone, in: screen.frame).contains(point)
        }

        if let zone = matchingZone {
            if activeZone != zone {
                activeZone = zone
                currentActiveZone = zone
                let threshold = dwellOverride?(zone) ?? dwellThreshold
                if threshold <= 0 {
                    fire(zone)
                } else {
                    startDwellTimer(for: zone)
                }
            }

        } else {

            clearActive()
        }
    }

    private func startDwellTimer(for zone: ScreenZone) {

        if pendingZone == zone, dwellTimer?.isValid == true { return }

        dwellTimer?.invalidate()
        pendingZone = zone
        let threshold = dwellOverride?(zone) ?? dwellThreshold
        let startDate = Date()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let timeRemaining = threshold - Date().timeIntervalSince(startDate)

                if !Self.isPoint(in: zone, at: NSEvent.mouseLocation) {
                    self.resetDwell()
                    return
                }

                if timeRemaining <= 0 {
                    self.dwellTimer?.invalidate()
                    self.dwellTimer = nil
                    self.pendingZone = nil
                    if Self.isPoint(in: zone, at: NSEvent.mouseLocation) {
                        self.fire(zone)
                    }
                    self.resetDwell()
                    return
                }

                let progress = min(max(1 - (timeRemaining / threshold), 0), 1)
                self.onDwellProgress?(zone, progress)
            }
        }
    }

    private static func isPoint(in zone: ScreenZone, at point: NSPoint) -> Bool {
        guard let screen = ZoneGeometry.screen(containing: point) else { return false }
        return ZoneGeometry.rect(for: zone, in: screen.frame).contains(point)
    }

    private func fire(_ zone: ScreenZone) {
        let now = Date()
        if let last = lastTriggerDate[zone], now.timeIntervalSince(last) < triggerCooldown { return }
        lastTriggerDate[zone] = now
        onZoneTrigger?(zone)
    }

    private func clearActive() {
        activeZone = nil
        currentActiveZone = nil
    }

    private func resetDwell() {
        let dwelledZone = pendingZone
        let wasDwelling = dwellTimer?.isValid == true
        dwellTimer?.invalidate()
        dwellTimer = nil
        pendingZone = nil
        activeZone = nil
        currentActiveZone = nil
        if wasDwelling, let dwelledZone {
            onDwellProgress?(dwelledZone, 0)
        }
    }
}
