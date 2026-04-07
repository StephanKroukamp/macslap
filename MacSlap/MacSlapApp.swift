import SwiftUI

@main
struct MacSlapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("MacSlap") {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 520, minHeight: 480)
                .onAppear {
                    // Ensure the window is visible and focused
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 520, height: 520)

        MenuBarExtra {
            MenuBarView(openMainWindow: {
                // Re-open the main window
                if let window = NSApplication.shared.windows.first(where: { $0.title == "MacSlap" || $0.contentView?.subviews.count ?? 0 > 0 }) {
                    window.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } else {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            })
            .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.fill")
                Text("\(appState.slapCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running in menu bar when window is closed
    }
}
