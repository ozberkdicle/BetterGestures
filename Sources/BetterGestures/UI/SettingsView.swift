import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    @Bindable var state: AppState
    @State private var pane: Pane? = .gestures
    @Environment(\.controlActiveState) private var activeState

    enum Pane: CaseIterable, Identifiable {
        case gestures, live, tuning, general

        var id: Self { self }

        var title: String {
            switch self {
            case .gestures: String(localized: "Jestler")
            case .live: String(localized: "Canlı")
            case .tuning: String(localized: "İnce ayar")
            case .general: String(localized: "Genel")
            }
        }

        var symbol: String {
            switch self {
            case .gestures: "hand.draw"
            case .live: "waveform"
            case .tuning: "slider.horizontal.3"
            case .general: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch pane ?? .gestures {
            case .gestures: GesturesPane(state: state).navigationTitle(Pane.gestures.title)
            case .live: LivePane(state: state).navigationTitle(Pane.live.title)
            case .tuning: TuningPane(state: state).navigationTitle(Pane.tuning.title)
            case .general: GeneralPane(state: state).navigationTitle(Pane.general.title)
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .onAppear {
            state.isSettingsOpen = true
            // show up in the dock and ⌘⇥ while the window is open, so it doesn't get lost behind other windows.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            state.isSettingsOpen = false
            state.isSettingsKey = false
            NSApp.setActivationPolicy(.accessory)
        }
        .onChange(of: activeState, initial: true) { _, newValue in
            state.isSettingsKey = newValue == .key
        }
    }
}
