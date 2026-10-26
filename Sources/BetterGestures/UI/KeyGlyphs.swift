import Carbon.HIToolbox
import GestureCore

/// shows a shortcut like menus do (⌃⇧⇥). letter/symbol keys are labeled with the active keyboard
/// layout, e.g. key 30 shows as "Ü" on the turkish layout.
@MainActor
enum KeyGlyphs {
    static func display(_ shortcut: KeyShortcut) -> String {
        modifiers(shortcut.modifiers) + keyLabel(shortcut.keyCode)
    }

    static func modifiers(_ modifiers: KeyShortcut.Modifiers) -> String {
        var s = ""
        if modifiers.contains(.function) { s += "fn " }
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s
    }

    static func keyLabel(_ keyCode: UInt16) -> String {
        if let special = special[keyCode] { return special }
        if let name = KeyShortcut.keyNames[keyCode], name.hasPrefix("f"), Int(name.dropFirst()) != nil {
            return name.uppercased()
        }
        let label = layoutCharacter(keyCode) ?? KeyShortcut.keyNames[keyCode] ?? "#\(keyCode)"
        return label.uppercased(with: .current)
    }

    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static func layoutCharacter(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                                  chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
