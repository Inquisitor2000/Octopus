import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ZoneStore
    @State private var editingZone: ScreenZone?
    @State private var trusted = ZoneStore.checkAccessibilityPermission()
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var showGhostingInfo = false
    @State private var showDwellInfo = false

    var body: some View {
        Form {
            Section {
                monitorLoginRow
                dwellRow
                ghostingRow
                accessibilityRow
            } header: {
                Label("Monitoring", systemImage: "cursorarrow.motionlines")
            }

            Section {
                zonesGrid
                Text("Click a zone to configure. Drag an app, file, folder, or script onto a zone to assign it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Zones", systemImage: "square.grid.3x3")
            }
        }
        .formStyle(.grouped)
        .padding(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
        .frame(minWidth: 640, minHeight: 620)
        .sheet(item: $editingZone) { zone in
            ZoneEditView(store: store, zone: zone)
        }
        .task {

            while !Task.isCancelled {
                let current = ZoneStore.checkAccessibilityPermission()
                if current != trusted {
                    let wasTrusted = trusted
                    trusted = current

                    if !wasTrusted && current { store.autoStartIfNeeded() }
                }
                let login = SMAppService.mainApp.status == .enabled
                if login != atLogin { atLogin = login }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func toggleLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
            atLogin = service.status == .enabled
        } catch {
            atLogin = service.status == .enabled
            let alert = NSAlert()
            alert.messageText = "Launch at Login Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private var monitorLoginRow: some View {
        HStack(spacing: 8) {
            Text("Enable monitoring")
                .frame(width: 130, alignment: .leading)
            Toggle("Enable monitoring", isOn: Binding(
                get: { store.monitoringEnabled },
                set: { store.toggleMonitoring($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Divider()
                .frame(height: 20)
                .padding(.trailing, 8)
            Toggle("Launch at startup", isOn: Binding(
                get: { atLogin },
                set: { toggleLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
        }
    }

    private var dwellRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Dwell threshold")
                Button { showDwellInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Waits the chosen time with the cursor in a zone before triggering its action. Off triggers instantly.")
                .popover(isPresented: $showDwellInfo, arrowEdge: .bottom) {
                    Text("Waits the chosen time with the cursor in a zone before triggering its action. Off triggers instantly.")
                        .font(.callout)
                        .padding(10)
                        .frame(width: 230)
                }
            }
            .frame(width: 130, alignment: .leading)
            Toggle("Dwell threshold", isOn: Binding(
                get: { store.dwellEnabled },
                set: { store.dwellEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Divider()
                .frame(height: 20)
                .padding(.trailing, 8)
            Text(String(format: "Dwell time: %.1fs", store.globalDwell))
                .monospacedDigit()
                .foregroundStyle(store.dwellEnabled ? Color.primary : Color.secondary)
            Spacer()
            Slider(value: Binding(
                get: { store.globalDwell },
                set: { store.globalDwell = $0 }
            ), in: 0.5...2.0, step: 0.5)
            .disabled(!store.dwellEnabled)
            .frame(maxWidth: 240)
        }
    }

    private var ghostingRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Corner ghosting")
                Button {
                    showGhostingInfo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Blocks the same corner from triggering again within the chosen time window.")
                .popover(isPresented: $showGhostingInfo, arrowEdge: .bottom) {
                    Text("Blocks the same corner from triggering again within the chosen time window.")
                        .font(.callout)
                        .padding(10)
                        .frame(width: 230)
                }
            }
            .frame(width: 130, alignment: .leading)
            Toggle("Corner ghosting", isOn: Binding(
                get: { store.ghostingEnabled },
                set: { store.ghostingEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Divider()
                .frame(height: 20)
                .padding(.trailing, 8)
            Text("Time: \(store.ghostingSeconds)s")
                .monospacedDigit()
                .foregroundStyle(store.ghostingEnabled ? Color.primary : Color.secondary)
            Spacer()
            Slider(value: Binding(
                get: { Double(store.ghostingSeconds) },
                set: { store.ghostingSeconds = min(max(Int($0.rounded()), 3), 9) }
            ), in: 3...9, step: 2)
            .disabled(!store.ghostingEnabled)
            .frame(maxWidth: 240)
        }
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        if !trusted {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Octopus needs Accessibility permission to watch the cursor.")
                Spacer()
                Button("Open System Settings…") {
                    ZoneStore.promptAccessibility()
                }
            }
            .font(.callout)
        }
    }

    private var zonesGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(ZoneGridItem.all) { item in
                switch item {
                case .zone(let zone):
                    ZoneCellView(store: store, zone: zone) {
                        editingZone = zone
                    }
                case .center:
                    CenterCellView()
                }
            }
        }
    }
}

struct ZoneEditView: View {
    @ObservedObject var store: ZoneStore
    let zone: ScreenZone
    @Environment(\.dismiss) private var dismiss

    @State private var type: TargetType
    @State private var path: String
    @State private var systemAction: SystemAction

    init(store: ZoneStore, zone: ScreenZone) {
        self.store = store
        self.zone = zone
        let action = store.assignments.first { $0.zoneRaw == zone.rawValue }?.action
        let isSystem = action?.type == .systemAction
        _type = State(initialValue: action?.type ?? .anything)
        _path = State(initialValue: isSystem ? "" : (action?.path ?? ""))
        _systemAction = State(initialValue: isSystem
                              ? (SystemAction(rawValue: action?.path ?? "") ?? .missionControl)
                              : .missionControl)
    }

    private var hasExistingAction: Bool {
        assignment?.action != nil
    }

    private var assignment: ZoneAssignment? {
        store.assignments.first { $0.zoneRaw == zone.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Assign action to \(zone.rawValue)")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                Picker("Type", selection: $type) {
                    ForEach(TargetType.allCases) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                .fixedSize()

                if type == .systemAction {
                    Picker("Action", selection: $systemAction) {
                        ForEach(SystemAction.allCases) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    .fixedSize()
                    .transition(.opacity)
                }

                Spacer()
            }

            if type != .systemAction {
                HStack {
                    TextField("Path to .app, file, folder, or script", text: $path)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        )
                    Button("Browse…") { browse() }
                }
                .transition(.opacity)
            }

            HStack {
                if hasExistingAction {
                    Button("Remove action", role: .destructive) {
                        store.clearAction(for: zone)
                        dismiss()
                    }
                }
                Spacer()
                Button("Assign") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.25), value: type)
    }

    private func save() {
        if type == .systemAction {
            store.setAction(TriggerAction(path: systemAction.rawValue, type: .systemAction), for: zone, enabled: true)
            return
        }
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            store.clearAction(for: zone)
            return
        }
        store.setAction(TriggerAction(path: trimmed, type: type), for: zone, enabled: true)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
    }
}
