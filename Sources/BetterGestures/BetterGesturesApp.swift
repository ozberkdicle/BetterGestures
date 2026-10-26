import SwiftUI

@main
struct BetterGesturesApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(nsImage: state.isEnabled ? MenuBarIcon.enabled : MenuBarIcon.disabled)
        }
        .menuBarExtraStyle(.menu)

        Window("BetterGestures", id: SettingsView.windowID) {
            SettingsView(state: state)
        }
        .defaultSize(width: 880, height: 640)
        .windowResizability(.contentMinSize)
        // starting with `--settings` opens the window (make settings).
        .defaultLaunchBehavior(ProcessInfo.processInfo.arguments.contains("--settings") ? .presented : .suppressed)
    }
}

private struct MenuContent: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Jestler etkin", isOn: $state.isEnabled)
        if !state.isAccessibilityTrusted {
            Button("⚠︎ Erişilebilirlik izni gerekli…") { openSettings() }
        }
        if let last = state.lastRecognized {
            Text("Son jest: \(last.gesture.title)")
        }

        Divider()

        Button("Ayarlar…") { openSettings() }
            .keyboardShortcut(",")

        Divider()

        Button("Çıkış") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openSettings() {
        openWindow(id: SettingsView.windowID)
        NSApp.activate()
    }
}
