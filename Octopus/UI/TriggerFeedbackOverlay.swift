import AppKit
import SwiftUI

enum TriggerFeedbackEffect: String, CaseIterable, Identifiable {
    case none
    case glow
    case flash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .glow: return "Dwell Glow"
        case .flash: return "Edge Flash"
        }
    }
}

enum TriggerSound: String, CaseIterable, Identifiable {
    case none
    case blow = "Blow"
    case bottle = "Bottle"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case tink = "Tink"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        default: return rawValue
        }
    }
}

@MainActor
final class ScreenEffectState: ObservableObject {
    enum BurstKind {
        case flash
        case glowPulse
    }

    @Published var effect: TriggerFeedbackEffect = .none
    @Published var zone: ScreenZone?
    @Published var progress: Double = 0
    @Published var burstID = 0
    @Published var pulseID = 0
    @Published var burstKind: BurstKind = .flash
    @Published var scale: CGFloat = 1
}

struct FeedbackLayerView: View {
    @ObservedObject var state: ScreenEffectState

    @State private var burstProgress: Double = 0
    @State private var burstScale: CGFloat = 0.2
    @State private var pulseActive = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let zone = state.zone, state.effect == .glow {
                    glowView(zone: zone, size: geo.size)
                }
                if let zone = state.zone, state.burstID > 0 {
                    burstView(zone: zone, size: geo.size)
                        .id(state.burstID)
                        .onAppear {
                            burstProgress = 0
                            burstScale = 0.2
                            withAnimation(.easeOut(duration: 0.45)) {
                                burstProgress = 1
                                burstScale = 1
                            }
                        }
                }
            }
        }
        .onChange(of: state.pulseID) { _, newValue in
            guard newValue > 0 else { return }
            pulseActive = true
            withAnimation(.easeOut(duration: 0.6)) {
                pulseActive = false
            }
        }
        .onChange(of: state.zone) { _, newValue in
            guard newValue == nil else { return }
            burstProgress = 0
            burstScale = 0.2
            pulseActive = false
        }
    }

    private func anchor(for zone: ScreenZone, in size: CGSize) -> CGPoint {
        switch zone {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: size.width, y: 0)
        case .bottomLeft: return CGPoint(x: 0, y: size.height)
        case .bottomRight: return CGPoint(x: size.width, y: size.height)
        case .topCenter: return CGPoint(x: size.width / 2, y: 0)
        case .bottomCenter: return CGPoint(x: size.width / 2, y: size.height)
        case .leftMiddle: return CGPoint(x: 0, y: size.height / 2)
        case .rightMiddle: return CGPoint(x: size.width, y: size.height / 2)
        }
    }

    private var fx: CGFloat { state.scale }

    private func glowView(zone: ScreenZone, size: CGSize) -> some View {
        let pulsing = pulseActive
        let level = max(state.progress, pulsing ? 0.7 : 0)
        let scale: CGFloat = pulsing ? 1.5 : 0.7 + 0.3 * state.progress
        let opacity: Double = pulsing ? 0.5 : 1
        return Circle()
            .fill(RadialGradient(
                colors: [Color.accentColor.opacity(0.85 * level), Color.accentColor.opacity(0)],
                center: .center,
                startRadius: 4 * fx,
                endRadius: 210 * fx
            ))
            .frame(width: 420 * fx, height: 420 * fx)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(.linear(duration: 0.05), value: state.progress)
            .position(anchor(for: zone, in: size))
    }

    @ViewBuilder
    private func burstView(zone: ScreenZone, size: CGSize) -> some View {
        switch state.burstKind {
        case .flash:
            if isCorner(zone) {
                cornerFlash(zone: zone, size: size)
            } else {
                edgeFlash(zone: zone, size: size)
            }
        case .glowPulse:
            EmptyView()
        }
    }

    private func originDot(at point: CGPoint) -> some View {
        Circle()
            .fill(Color.white.opacity(1 - burstProgress))
            .frame(width: min(12 * fx, 24), height: min(12 * fx, 24))
            .position(point)
    }

    private func cornerFlash(zone: ScreenZone, size: CGSize) -> some View {
        let fade = 1 - burstProgress
        return ZStack {
            wedgePath(zone: zone, size: size, radius: 150 * burstScale * fx)
                .fill(Color.accentColor.opacity(0.5 * fade))
            cornerSweeps(zone: zone, size: size, fraction: CGFloat(burstProgress), fade: fade)
            originDot(at: anchor(for: zone, in: size))
        }
    }

    @ViewBuilder
    private func cornerSweeps(zone: ScreenZone, size: CGSize, fraction: CGFloat, fade: Double) -> some View {
        let lengthFactor = min(0.55 * fx, 1.0)
        let w = size.width * fraction * lengthFactor
        let h = size.height * fraction * lengthFactor
        let fill = Color.accentColor.opacity(fade)
        switch zone {
        case .topLeft:
            Rectangle().fill(fill).frame(width: w, height: 3).position(x: w / 2, y: 4)
            Rectangle().fill(fill).frame(width: 3, height: h).position(x: 4, y: h / 2)
        case .topRight:
            Rectangle().fill(fill).frame(width: w, height: 3).position(x: size.width - w / 2, y: 4)
            Rectangle().fill(fill).frame(width: 3, height: h).position(x: size.width - 4, y: h / 2)
        case .bottomLeft:
            Rectangle().fill(fill).frame(width: w, height: 3).position(x: w / 2, y: size.height - 4)
            Rectangle().fill(fill).frame(width: 3, height: h).position(x: 4, y: size.height - h / 2)
        case .bottomRight:
            Rectangle().fill(fill).frame(width: w, height: 3).position(x: size.width - w / 2, y: size.height - 4)
            Rectangle().fill(fill).frame(width: 3, height: h).position(x: size.width - 4, y: size.height - h / 2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func edgeFlash(zone: ScreenZone, size: CGSize) -> some View {
        let fade = 1 - burstProgress
        let sweep = CGFloat(burstProgress)
        let lengthFactor = min(0.55 * fx, 1.0)
        switch zone {
        case .topCenter:
            edgeStrip(length: size.width * sweep * lengthFactor, center: CGPoint(x: size.width / 2, y: 4), horizontal: true, fade: fade)
        case .bottomCenter:
            edgeStrip(length: size.width * sweep * lengthFactor, center: CGPoint(x: size.width / 2, y: size.height - 4), horizontal: true, fade: fade)
        case .leftMiddle:
            edgeStrip(length: size.height * sweep * lengthFactor, center: CGPoint(x: 4, y: size.height / 2), horizontal: false, fade: fade)
        case .rightMiddle:
            edgeStrip(length: size.height * sweep * lengthFactor, center: CGPoint(x: size.width - 4, y: size.height / 2), horizontal: false, fade: fade)
        default:
            EmptyView()
        }
    }

    private func edgeStrip(length: CGFloat, center: CGPoint, horizontal: Bool, fade: Double) -> some View {
        let haloThickness = min(14 * fx, 30)
        let coreThickness = min(3 * fx, 8)
        let tipSize = min(6 * fx, 14)
        return ZStack {
            Rectangle()
                .fill(Color.accentColor.opacity(0.25 * fade))
                .frame(width: horizontal ? length : haloThickness, height: horizontal ? haloThickness : length)
                .position(center)
            Rectangle()
                .fill(Color.accentColor.opacity(fade))
                .frame(width: horizontal ? length : coreThickness, height: horizontal ? coreThickness : length)
                .position(center)
            Circle()
                .fill(Color.white.opacity(fade))
                .frame(width: tipSize, height: tipSize)
                .position(horizontal ? CGPoint(x: center.x - length / 2, y: center.y) : CGPoint(x: center.x, y: center.y - length / 2))
            Circle()
                .fill(Color.white.opacity(fade))
                .frame(width: tipSize, height: tipSize)
                .position(horizontal ? CGPoint(x: center.x + length / 2, y: center.y) : CGPoint(x: center.x, y: center.y + length / 2))
        }
    }

    private func wedgePath(zone: ScreenZone, size: CGSize, radius: CGFloat) -> Path {
        let center = anchor(for: zone, in: size)
        let (start, end) = arcRange(for: zone)
        return Path { path in
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            path.addLine(to: center)
            path.closeSubpath()
        }
    }

    private func arcRange(for zone: ScreenZone) -> (Angle, Angle) {
        switch zone {
        case .topLeft: return (.degrees(0), .degrees(90))
        case .topRight: return (.degrees(90), .degrees(180))
        case .bottomRight: return (.degrees(180), .degrees(270))
        case .bottomLeft: return (.degrees(270), .degrees(360))
        case .topCenter: return (.degrees(0), .degrees(180))
        case .bottomCenter: return (.degrees(180), .degrees(360))
        case .leftMiddle: return (.degrees(270), .degrees(450))
        case .rightMiddle: return (.degrees(90), .degrees(270))
        }
    }

    private func isCorner(_ zone: ScreenZone) -> Bool {
        switch zone {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}

@MainActor
final class TriggerFeedbackManager {
    private weak var store: ZoneStore?
    private var states: [String: ScreenEffectState] = [:]
    private var windows: [String: NSWindow] = [:]
    private var hideWork: [String: DispatchWorkItem] = [:]
    private var activeSounds: [NSSound] = []
    private var screenObserver: NSObjectProtocol?
    private var soundObserver: NSObjectProtocol?

    init(store: ZoneStore) {
        self.store = store
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuild()
            }
        }
        soundObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSSoundDidFinishPlaying"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let finishedID = (note.object as? NSSound).map { ObjectIdentifier($0) }
            Task { @MainActor in
                guard let self, let id = finishedID,
                      let index = self.activeSounds.firstIndex(where: { ObjectIdentifier($0) == id })
                else { return }
                self.activeSounds.remove(at: index)
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            if let soundObserver { NotificationCenter.default.removeObserver(soundObserver) }
        }
    }

    private func key(for screen: NSScreen) -> String {
        NSStringFromRect(screen.frame)
    }

    func showProgress(zone: ScreenZone, progress: Double) {
        guard let store, store.monitoringEnabled, store.feedbackEffect == .glow,
              let screen = screen(for: zone) else { return }
        let key = self.key(for: screen)
        let state = state(for: key)
        let window = window(for: key, screen: screen)
        hideWork[key]?.cancel()
        if progress <= 0 {
            state.zone = nil
            state.progress = 0
            window.orderOut(nil)
            return
        }
        state.effect = store.feedbackEffect
        state.zone = zone
        state.progress = progress
        window.orderFront(nil)
    }

    func trigger(zone: ScreenZone) {
        guard let store, store.monitoringEnabled, store.feedbackEnabled else { return }
        let effect = store.feedbackEffect
        guard effect != .none, let screen = screen(for: zone) else { return }
        if store.soundEffect != .none {
            playSound(store.soundEffect)
        }
        let key = self.key(for: screen)
        let state = state(for: key)
        let window = window(for: key, screen: screen)
        hideWork[key]?.cancel()
        window.orderFront(nil)
        state.scale = CGFloat(store.feedbackScale)
        switch effect {
        case .glow:
            state.burstKind = .glowPulse
            state.pulseID += 1
        case .flash: state.burstKind = .flash
        case .none: return
        }
        state.effect = effect
        state.zone = zone
        state.burstID += 1
        scheduleHide(key: key, after: 0.6)
    }

    private func playSound(_ sound: TriggerSound) {
        guard sound != .none else { return }
        let raw = sound.rawValue
        let player: NSSound?
        if let loaded = NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/\(raw).aiff"), byReference: false) {
            player = loaded
        } else {
            player = NSSound(named: raw)
        }
        guard let player else { return }
        player.volume = Float(store?.soundVolume ?? 0.7)
        player.play()
        activeSounds.append(player)
    }

    func hideAll() {
        for (_, work) in hideWork { work.cancel() }
        hideWork.removeAll()
        for state in states.values {
            state.zone = nil
            state.progress = 0
        }
        for window in windows.values { window.orderOut(nil) }
    }

    private func screen(for zone: ScreenZone) -> NSScreen? {
        ZoneGeometry.screen(containing: NSEvent.mouseLocation)
    }

    private func state(for key: String) -> ScreenEffectState {
        if let state = states[key] { return state }
        let state = ScreenEffectState()
        states[key] = state
        return state
    }

    private func window(for key: String, screen: NSScreen) -> NSWindow {
        if let window = windows[key] { return window }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FeedbackLayerView(state: state(for: key)))
        window.orderOut(nil)
        windows[key] = window
        return window
    }

    private func scheduleHide(key: String, after delay: Double) {
        hideWork[key]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.states[key]?.zone = nil
                self.states[key]?.progress = 0
                self.windows[key]?.orderOut(nil)
            }
        }
        hideWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func rebuild() {
        let currentKeys = Set(NSScreen.screens.map { key(for: $0) })
        for (key, window) in windows where !currentKeys.contains(key) {
            window.orderOut(nil)
        }
        windows = windows.filter { currentKeys.contains($0.key) }
        states = states.filter { currentKeys.contains($0.key) }
        hideWork = hideWork.filter { currentKeys.contains($0.key) }
        for screen in NSScreen.screens {
            let key = self.key(for: screen)
            if let window = windows[key] {
                window.setFrame(screen.frame, display: true)
            } else {
                _ = window(for: key, screen: screen)
            }
        }
    }
}
