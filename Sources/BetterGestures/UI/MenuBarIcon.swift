import AppKit

/// menu bar icon: a rounded rect in trackpad proportions, dimmed while gestures are off.
/// it's a template image, so it follows light/dark menu bars on its own.
@MainActor
enum MenuBarIcon {
    static let enabled = make(enabled: true)
    static let disabled = make(enabled: false)

    static func make(enabled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            let color = NSColor.black.withAlphaComponent(enabled ? 1 : 0.45)
            // magic trackpad proportions (~156×110 mm).
            let pad = NSRect(x: 1.5, y: 1.75, width: 19, height: 12.5)
            let outline = NSBezierPath(roundedRect: pad, xRadius: 2.8, yRadius: 2.8)
            outline.lineWidth = 1.5
            color.setStroke()
            outline.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = enabled
            ? String(localized: "BetterGestures (etkin)") : String(localized: "BetterGestures (kapalı)")
        return image
    }
}
