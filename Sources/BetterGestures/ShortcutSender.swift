import ApplicationServices
import CoreGraphics
import GestureCore

enum ShortcutSender {
    /// sends the shortcut at the hid level like a real keyboard: modifiers go down, the key is pressed
    /// and released, modifiers come up in reverse order. sending modifiers only as flags on the key event
    /// can leave them "held" in the system (the dock stops showing, for one).
    /// without the accessibility permission the events are silently dropped. events go out in order
    /// on their own queue, so the caller (touch callback, event filter) doesn't wait.
    static func send(_ shortcut: KeyShortcut) {
        queue.async { post(shortcut) }
    }

    private static let queue = DispatchQueue(label: "dev.ozberk.BetterGestures.shortcuts", qos: .userInteractive)

    private static func post(_ shortcut: KeyShortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers = modifierKeys.filter { shortcut.modifiers.contains($0.modifier) }
        var flags: CGEventFlags = []
        var events: [CGEvent?] = []

        for m in modifiers {
            flags.insert(m.flag)
            events.append(modifierEvent(source, m.keyCode, flags: flags))
        }
        let keyFlags = flags.union(hardwareFlags(for: shortcut.keyCode))
        events.append(keyEvent(source, CGKeyCode(shortcut.keyCode), down: true, flags: keyFlags))
        events.append(keyEvent(source, CGKeyCode(shortcut.keyCode), down: false, flags: keyFlags))
        for m in modifiers.reversed() {
            flags.remove(m.flag)
            events.append(modifierEvent(source, m.keyCode, flags: flags))
        }

        for event in events {
            event?.post(tap: .cghidEventTap)
        }
    }

    private static let modifierKeys: [(modifier: KeyShortcut.Modifiers, keyCode: CGKeyCode, flag: CGEventFlags)] = [
        (.control, 59, .maskControl),
        (.option, 58, .maskAlternate),
        (.shift, 56, .maskShift),
        (.command, 55, .maskCommand),
        (.function, 63, .maskSecondaryFn),
    ]

    /// a real keyboard sends numericPad+fn with arrow keys and fn with f/navigation keys.
    /// system shortcuts (e.g. ⌃← for spaces) are registered with these flags and won't match without them.
    private static func hardwareFlags(for keyCode: UInt16) -> CGEventFlags {
        if (123...126).contains(keyCode) { return [.maskNumericPad, .maskSecondaryFn] }
        return KeyShortcut.hardwareSetsFunctionFlag(keyCode: keyCode) ? [.maskSecondaryFn] : []
    }

    private static func keyEvent(_ source: CGEventSource?, _ code: CGKeyCode, down: Bool, flags: CGEventFlags) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        return event
    }

    private static func modifierEvent(_ source: CGEventSource?, _ code: CGKeyCode, flags: CGEventFlags) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        event?.type = .flagsChanged
        event?.flags = flags
        return event
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// shows the system permission prompt (does nothing if already granted).
    static func request() {
        // kAXTrustedCheckOptionPrompt is a global `var`, swift 6 won't let us use it directly.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
