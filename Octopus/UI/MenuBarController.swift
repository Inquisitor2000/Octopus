import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private let store: ZoneStore
    private var monitorMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(store: ZoneStore) {
        self.store = store
        setupStatusItem()
        store.autoStartIfNeeded()

        store.$monitoringEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)
        store.$assignments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)

        updateMenu()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            var image = NSImage(named: "OctopusImage")
            if image == nil {
                image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Octopus")
            }
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()

        monitorMenuItem = menu.addItem(withTitle: "Start Octopus",
                                       action: #selector(toggleMonitoring(_:)),
                                       keyEquivalent: "m")
        monitorMenuItem?.target = self

        let settingsItem = menu.addItem(withTitle: "Open Settings…",
                                        action: #selector(openSettings(_:)),
                                        keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = Self.symbol("gearshape")

        menu.addItem(.separator())

        let quitItem = menu.addItem(withTitle: "Quit Octopus",
                                    action: #selector(NSApplication.terminate(_:)),
                                    keyEquivalent: "q")
        quitItem.target = NSApp

        item.menu = menu
        statusItem = item
        updateMenu()
    }

    func updateMenu() {
        let on = store.monitoringEnabled
        monitorMenuItem?.title = on ? "Stop Octopus" : "Start Octopus"
        monitorMenuItem?.image = Self.symbol(on ? "circle.fill" : "circle",
                                             tint: .white)
    }

    private static func symbol(_ name: String, tint: NSColor? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        guard let tint else { return base }
        return base.withSymbolConfiguration(.init(paletteColors: [tint])) ?? base
    }

    @objc private func toggleMonitoring(_ sender: Any?) {
        store.toggleMonitoring(!store.monitoringEnabled)
        updateMenu()
    }

    @objc private func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Octopus Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 680, height: 640))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
