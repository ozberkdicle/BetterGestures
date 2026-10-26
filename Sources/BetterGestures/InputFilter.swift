import CoreGraphics
import Foundation
import os

/// filters trackpad scroll and click events before they reach apps:
///
/// - scroll: swallows scrolls while 3+ fingers are down. with the system's 3-finger gestures off,
///   macos turns three fingers into a scroll; this way the movement is only our gesture.
///   two-finger scrolling and mouse wheels aren't touched.
/// - click: asks `onClick` on every press; if the click was used as a gesture, the press, drags
///   and release are swallowed.
///
/// the tap runs on its own thread; `blockedTouch` and `swallowedButton` are only used there.
final class InputFilter: @unchecked Sendable {
    private static let log = Logger(subsystem: DebugLogger.subsystem, category: "input")

    struct Options: Sendable, Equatable {
        var blockScroll = false
        var captureClicks = false
    }

    private let fingerState: @Sendable () -> TouchPipeline.FingerState
    /// true if the click was used as a gesture; the click is swallowed then.
    private let onClick: @Sendable () -> Bool
    private let options = OSAllocatedUnfairLock(initialState: Options())
    private var tap: CFMachPort?
    /// the touch that had 3+ fingers down. as fingers lift one by one the system starts a new scroll
    /// with the remaining two; that and the momentum after it belong to this touch and get swallowed.
    private var blockedTouch: Int?
    /// button whose press was swallowed; its events are swallowed until it's released.
    private var swallowedButton: CGMouseButton?

    init(fingerState: @escaping @Sendable () -> TouchPipeline.FingerState, onClick: @escaping @Sendable () -> Bool) {
        self.fingerState = fingerState
        self.onClick = onClick
    }

    var isInstalled: Bool { tap != nil }

    /// with options off events pass through untouched; the tap stays installed.
    func setOptions(_ value: Options) {
        options.withLock { $0 = value }
    }

    /// installs the event tap. fails (false) without the accessibility permission.
    /// call from the main thread.
    func install() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: inputTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        nonisolated(unsafe) let port = tap
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "InputFilter"
        thread.qualityOfService = .userInteractive
        thread.start()
        Self.log.notice("event filter installed")
        return true
    }

    /// true if the event should be dropped.
    fileprivate func shouldDrop(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // the system found the tap too slow and disabled it; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // we may have missed a release while disabled; don't leave a button stuck.
            swallowedButton = nil
            Self.log.notice("event filter was disabled by the system, turned it back on")
            return false
        case .scrollWheel:
            return shouldDropScroll(event)
        case .leftMouseDown, .rightMouseDown:
            let button: CGMouseButton = type == .leftMouseDown ? .left : .right
            let swallow = options.withLock({ $0.captureClicks }) && fingerState().maxCount >= 3 && onClick()
            // new press: if the release of an earlier swallowed press got lost, don't swallow this one's events.
            swallowedButton = swallow ? button : nil
            return swallow
        case .leftMouseDragged, .leftMouseUp:
            return dropButtonEvent(.left, released: type == .leftMouseUp)
        case .rightMouseDragged, .rightMouseUp:
            return dropButtonEvent(.right, released: type == .rightMouseUp)
        default:
            return false
        }
    }

    private func dropButtonEvent(_ button: CGMouseButton, released: Bool) -> Bool {
        guard swallowedButton == button else { return false }
        if released { swallowedButton = nil }
        return true
    }

    private func shouldDropScroll(_ event: CGEvent) -> Bool {
        guard options.withLock({ $0.blockScroll }) else {
            blockedTouch = nil
            return false
        }
        // leave mouse wheel (non-continuous) scrolls alone.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else { return false }

        let fingers = fingerState()
        if fingers.maxCount >= 3 {
            if blockedTouch != fingers.touchEpoch { Self.log.info("blocked a 3+ finger scroll") }
            blockedTouch = fingers.touchEpoch
            return true
        }
        // tail or momentum of the same touch; a new touch goes through.
        return blockedTouch == fingers.touchEpoch
    }
}

private func inputTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let filter = Unmanaged<InputFilter>.fromOpaque(refcon).takeUnretainedValue()
    return filter.shouldDrop(type, event) ? nil : Unmanaged.passUnretained(event)
}
