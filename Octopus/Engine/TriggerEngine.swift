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
    private var dwellStartDate: Date?
    private var lastMousePoint = NSPoint.zero
    private var watchdogTimer: Timer?
    private var lastEvaluation = Date.distantPast

    public var dwellThreshold: TimeInterval = 0.35
    public var dwellOverride: ((ScreenZone) -> TimeInterval?)?
    public var onZoneTrigger: ((ScreenZone) -> Void)?
    public var onDwellProgress: ((ScreenZone, Double) -> Void)?

    public var triggerCooldown: TimeInterval = 8
    private var lastTriggerDate: [ScreenZone: Date] = [:]

    private var zoneRectsCache: [CGRect: [ScreenZone: CGRect]] = [:]
    private var screenChangeObserver: NSObjectProtocol?

    public init() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.zoneRectsCache.removeAll()
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let observer = screenChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    private func zoneRects(for frame: CGRect) -> [ScreenZone: CGRect] {
        if let cached = zoneRectsCache[frame] { return cached }
        let rects = Dictionary(uniqueKeysWithValues: ScreenZone.allCases.map { ($0, ZoneGeometry.rect(for: $0, in: frame)) })
        zoneRectsCache[frame] = rects
        return rects
    }

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
            // The tap's CFRunLoopSource is added to the main run loop
            // (see createTap), so this callback already runs on the main
            // thread. assumeIsolated avoids allocating a Task per mouse event.
            MainActor.assumeIsolated {
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
        lastMousePoint = point

        guard let screen = ZoneGeometry.screen(containing: point) else {
            resetDwell()
            return
        }

        let rects = zoneRects(for: screen.frame)

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for r in rects.values {
            minX = min(minX, r.minX)
            minY = min(minY, r.minY)
            maxX = max(maxX, r.maxX)
            maxY = max(maxY, r.maxY)
        }
        if point.x < minX || point.x > maxX || point.y < minY || point.y > maxY {
            resetDwell()
            return
        }

        let matchingZone = ScreenZone.allCases.first { rects[$0]!.contains(point) }

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
            } else if let start = dwellStartDate, pendingZone == zone {
                let threshold = dwellOverride?(zone) ?? dwellThreshold
                let progress = min(max(now.timeIntervalSince(start) / threshold, 0), 1)
                onDwellProgress?(zone, progress)
            }
        } else {
            resetDwell()
        }
    }

    private func startDwellTimer(for zone: ScreenZone) {

        if pendingZone == zone, dwellTimer?.isValid == true { return }

        dwellTimer?.invalidate()
        pendingZone = zone
        dwellStartDate = Date()
        let threshold = dwellOverride?(zone) ?? dwellThreshold
        dwellTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let completionZone = self.pendingZone
                self.dwellTimer?.invalidate()
                self.dwellTimer = nil
                self.pendingZone = nil
                self.dwellStartDate = nil
                if let completionZone, Self.isPoint(in: completionZone, at: self.lastMousePoint) {
                    self.fire(completionZone)
                }
                self.resetDwell()
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

    private func resetDwell() {
        let dwelledZone = pendingZone
        let wasDwelling = dwellTimer?.isValid == true
        dwellTimer?.invalidate()
        dwellTimer = nil
        pendingZone = nil
        dwellStartDate = nil
        activeZone = nil
        currentActiveZone = nil
        if wasDwelling, let dwelledZone {
            onDwellProgress?(dwelledZone, 0)
        }
    }
}
