import GestureCore
import SwiftUI

struct GesturesPane: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $state.isEnabled) {
                    Text("Jestler etkin")
                    Text(state.isSettingsKey
                         ? "Bu pencere öndeyken kısayollar gönderilmez. Jestleri deneyin; tanınan satır yanar."
                         : "Tanınan jestler atanan kısayolu gönderir.")
                }
                .toggleStyle(.switch)
                if !state.isAccessibilityTrusted {
                    PermissionWarning(state: state)
                }
            }

            ForEach(GestureGroup.allCases) { group in
                Section {
                    ForEach(group.gestures) { gesture in
                        GestureRow(gesture: gesture, state: state)
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if let footer = group.footer {
                        Text(footer).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GestureRow: View {
    let gesture: Gesture
    @Bindable var state: AppState
    @State private var flash = false

    private var shortcut: KeyShortcut? { state.bindings[gesture] }

    var body: some View {
        HStack(spacing: 12) {
            GestureGlyph(gesture: gesture, highlighted: flash)
            VStack(alignment: .leading, spacing: 2) {
                Text(gesture.title)
                Text(gesture.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let preset = ShortcutPreset.matching(shortcut) {
                Text(preset.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ShortcutField(shortcut: shortcut) { state.setShortcut($0, for: gesture) }
            PresetMenu(current: shortcut) { state.setShortcut($0, for: gesture) }
        }
        .padding(.vertical, 2)
        .onChange(of: state.lastRecognized) { _, entry in
            guard entry?.gesture == gesture else { return }
            flash = true
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                flash = false
            }
        }
    }
}

struct PermissionWarning: View {
    let state: AppState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Erişilebilirlik izni yok")
                Text("İzin verilmeden kısayollar gönderilemez.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("İzin iste") { state.requestAccessibility() }
            Button("Ayarları aç") { state.openAccessibilitySettings() }
        }
    }
}
