import SwiftUI
import AppKit

@main
struct ENETForwardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = ForwarderViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(vm: vm)
        } label: {
            // Icon reflects running state.
            Image(systemName: vm.isRunning ? "antenna.radiowaves.left.and.right" : "car")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keeps the app menu-bar-only (no Dock icon) when run as a bare executable.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
