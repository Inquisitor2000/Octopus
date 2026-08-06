import SwiftUI

@main
struct OctopusApp: App {
    @StateObject private var store: ZoneStore
    @StateObject private var menuBarController: MenuBarController

    init() {
        let store = ZoneStore()
        _store = StateObject(wrappedValue: store)
        _menuBarController = StateObject(wrappedValue: MenuBarController(store: store))
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(menuBarController)
        }
    }
}
