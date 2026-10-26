import Foundation

/// a keyboard shortcut parsed from text like "cmd+shift+]".
/// keys are physical positions (ansi virtual key codes), independent of the active keyboard layout.
public struct KeyShortcut: Sendable, Equatable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
        public static let function = Modifiers(rawValue: 1 << 4)
    }

    public enum ParseError: Error, Equatable, Hashable {
        case empty
        /// only modifiers, no key (e.g. "cmd+shift").
        case missingKey(String)
        case unknownToken(String)
        case multipleKeys(String)
    }

    public var modifiers: Modifiers
    public var keyCode: UInt16
    /// the original text, for logs and menus.
    public var text: String

    public init(modifiers: Modifiers, keyCode: UInt16, text: String) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.text = text
    }

    /// shortcut from a recorded key press; the text is in the canonical form written to the config
    /// (e.g. "ctrl+shift+tab"). unknown keys become "keycode:N".
    public init(modifiers: Modifiers, keyCode: UInt16) {
        var parts: [String] = []
        if modifiers.contains(.function) { parts.append("fn") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(Self.keyNames[keyCode] ?? "keycode:\(keyCode)")
        self.init(modifiers: modifiers, keyCode: keyCode, text: parts.joined(separator: "+"))
    }

    /// same key combination? (regardless of how the text is written)
    public func sameKeys(as other: KeyShortcut) -> Bool {
        modifiers == other.modifiers && keyCode == other.keyCode
    }

    /// a real keyboard sets the fn flag on these keys by itself (arrows, f and navigation keys).
    /// when recording, that flag isn't counted as a modifier; it's added back when sending.
    public static func hardwareSetsFunctionFlag(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 96...101, 103, 105...107, 109, 111, 113...126: true
        default: false
        }
    }

    /// key code → name used in the config. picks one of the synonyms.
    public static let keyNames: [UInt16: String] = {
        var names = Dictionary(keyCodes.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        names[36] = "return"
        names[51] = "delete"
        names[53] = "escape"
        return names
    }()

    /// format: modifiers and a single key, joined with "+". case-insensitive.
    /// use "keycode:30" for a raw key code.
    public init(parsing text: String) throws(ParseError) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw .empty }

        var modifiers: Modifiers = []
        var keyCode: UInt16?
        for raw in trimmed.split(separator: "+", omittingEmptySubsequences: false) {
            let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if let modifier = Self.modifierNames[token] {
                modifiers.insert(modifier)
                continue
            }
            let code: UInt16
            if token.hasPrefix("keycode:"), let value = UInt16(token.dropFirst("keycode:".count)) {
                code = value
            } else if let value = Self.keyCodes[token] {
                code = value
            } else {
                throw .unknownToken(token)
            }
            guard keyCode == nil else { throw .multipleKeys(trimmed) }
            keyCode = code
        }
        guard let keyCode else { throw .missingKey(trimmed) }
        self.init(modifiers: modifiers, keyCode: keyCode, text: trimmed)
    }

    public var description: String { text }

    static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "alt": .option, "opt": .option, "option": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
        "fn": .function,
    ]

    /// carbon kVK_* values (ansi physical layout).
    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
