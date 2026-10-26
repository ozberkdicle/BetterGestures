import AppKit
import GestureCore
import SwiftUI

/// shortcut box that starts recording when clicked. records the physical key; ⎋ cancels.
struct ShortcutField: View {
    let shortcut: KeyShortcut?
    let onChange: (KeyShortcut?) -> Void

    @State private var isRecording = false
    @State private var heldModifiers: KeyShortcut.Modifiers = []
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(.body, design: .rounded).weight(shortcut == nil && !isRecording ? .regular : .medium))
                .foregroundStyle(shortcut == nil && !isRecording ? .secondary : .primary)
                .lineLimit(1)
                .frame(minWidth: 92)
            if shortcut != nil, !isRecording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Kısayolu kaldır")
                .accessibilityLabel("Kısayolu kaldır")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isRecording ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { isRecording ? stop() : start() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRecording ? "Kısayol kaydediliyor" : "Kısayol: \(label)")
        .accessibilityAction { isRecording ? stop() : start() }
        .onDisappear { stop() }
        .help(isRecording ? "Kısayola basın · ⎋ iptal" : "Kısayol kaydetmek için tıklayın")
        .animation(.easeOut(duration: 0.15), value: isRecording)
    }

    private var label: String {
        if isRecording {
            return heldModifiers.isEmpty ? String(localized: "Tuşlara basın…") : KeyGlyphs.modifiers(heldModifiers) + "…"
        }
        return shortcut.map(KeyGlyphs.display) ?? String(localized: "Kısayol ata")
    }

    private func start() {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        heldModifiers = []
    }

    /// true if the event was consumed (so it doesn't reach the app, e.g. menu shortcuts).
    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        var modifiers = Self.modifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return false
        }
        if event.keyCode == 53, modifiers.isEmpty {  // ⎋
            stop()
            return true
        }
        if KeyShortcut.hardwareSetsFunctionFlag(keyCode: event.keyCode) {
            modifiers.remove(.function)
        }
        onChange(KeyShortcut(modifiers: modifiers, keyCode: event.keyCode))
        stop()
        return true
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyShortcut.Modifiers {
        var m: KeyShortcut.Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.function) { m.insert(.function) }
        return m
    }
}

/// preset actions menu.
struct PresetMenu: View {
    let current: KeyShortcut?
    let onSelect: (KeyShortcut?) -> Void

    var body: some View {
        Menu {
            ForEach(ShortcutPreset.groups) { group in
                Menu(group.title) {
                    ForEach(group.presets) { preset in
                        Button {
                            onSelect(preset.shortcut)
                        } label: {
                            Text(verbatim: "\(preset.name)   \(KeyGlyphs.display(preset.shortcut))")
                        }
                    }
                }
            }
            if current != nil {
                Divider()
                Button("Kısayolu kaldır", role: .destructive) { onSelect(nil) }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .accessibilityLabel("Hazır işlemler")
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Hazır işlemlerden seç")
    }
}
