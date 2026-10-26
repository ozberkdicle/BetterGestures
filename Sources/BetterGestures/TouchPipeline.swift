import Foundation
import GestureCore
import os

/// the touch side: reads settings under a lock, processes the frame, acts on gesture decisions.
/// `handle` is called serially by the bridge; the double-tap timer runs on its own queue, so the
/// recognizer and logger are guarded by `lock`.
final class TouchPipeline: @unchecked Sendable {
    struct Settings: Sendable {
        var enabled = false
        var debug = false
        /// while the settings window is in front: gestures are recognized and reported but no shortcut
        /// is sent, and unmapped double taps are awaited too so they show up while trying them.
        var previewing = false
        var bindings: [Gesture: KeyShortcut] = [:]
        var tuning = RecognizerTuning()
    }

    /// a gesture decision passed to the ui.
    struct Event: Sendable {
        var gesture: Gesture
        var recognized: Bool
        /// the shortcut sent (or to be sent) if recognized, the reason if rejected.
        var detail: String
        var sent: Bool
    }

    private static let log = Logger(subsystem: DebugLogger.subsystem, category: "gesture")
    private let settings = OSAllocatedUnfairLock(initialState: Settings())
    private let frames = OSAllocatedUnfairLock(initialState: [UInt64: TouchFrame]())
    private let fingers = OSAllocatedUnfairLock(initialState: FingerState())
    private let eventHandler = OSAllocatedUnfairLock<(@Sendable (Event) -> Void)?>(initialState: nil)
    private let timerQueue = DispatchQueue(label: "dev.ozberk.BetterGestures.flush")

    private let lock = NSLock()
    private let logger = DebugLogger()
    private var recognizer = GestureRecognizer()
    /// device clock → `systemUptime` offset; devices timestamp frames with their own clocks.
    private var clockOffsets: [UInt64: Double] = [:]
    private var scheduledDeadlines: [UInt64: Double] = [:]

    func apply(_ newValue: Settings) {
        settings.withLock { $0 = newValue }
    }

    /// gesture decisions go to this closure (on the touch side's thread).
    func setEventHandler(_ handler: @escaping @Sendable (Event) -> Void) {
        eventHandler.withLock { $0 = handler }
    }

    /// latest frame of each device, for the live view.
    func latestFrames() -> [UInt64: TouchFrame] {
        frames.withLock { $0 }
    }

    /// pressed (`making`/`touching`) fingers on each trackpad; read by the event filter.
    struct FingerState: Sendable {
        var counts: [UInt64: Int] = [:]
        /// goes up every time the first finger lands on an otherwise empty set of trackpads, to tell
        /// events of one touch (including lift-off and momentum after it) from the next touch.
        var touchEpoch = 0

        var maxCount: Int { counts.values.max() ?? 0 }
    }

    func fingerState() -> FingerState {
        fingers.withLock { $0 }
    }

    func handle(_ frame: TouchFrame) {
        let current = settings.withLock { $0 }
        frames.withLock { $0[frame.deviceID] = frame }
        let pressed = frame.touches.count { $0.phase == .making || $0.phase == .touching }
        fingers.withLock { state in
            if state.maxCount == 0, pressed > 0 { state.touchEpoch += 1 }
            state.counts[frame.deviceID] = pressed
        }

        lock.lock()
        defer { lock.unlock() }
        if current.debug { logger.log(frame) }
        clockOffsets[frame.deviceID] = ProcessInfo.processInfo.systemUptime - frame.timestamp
        configure(current)
        deliver(recognizer.process(frame), current)
        scheduleFlushes()
    }

    /// trackpad was clicked (from the event filter's thread). true if the click was recognized as a
    /// gesture and its shortcut sent, or shown in the settings window: the click should be swallowed.
    func click() -> Bool {
        let current = settings.withLock { $0 }
        lock.lock()
        defer { lock.unlock() }
        let results = recognizer.click()
        deliver(results, current)
        guard case .recognized(let gesture)? = results.last else { return false }
        return current.enabled && (current.previewing || current.bindings[gesture] != nil)
    }

    /// when listening stops or devices are rescanned: fingers left "down" on a device that stopped
    /// sending frames shouldn't fool the scroll and click filter.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        recognizer.reset()
        clockOffsets = [:]
        scheduledDeadlines = [:]
        frames.withLock { $0 = [:] }
        fingers.withLock { $0.counts = [:] }
    }

    /// if the second tap never comes the trackpad sends no frames; the pending single tap is
    /// released from here when its time is up.
    private func flushDue() {
        let current = settings.withLock { $0 }
        lock.lock()
        defer { lock.unlock() }
        configure(current)
        let now = ProcessInfo.processInfo.systemUptime
        for (device, offset) in clockOffsets {
            deliver(recognizer.flush(deviceID: device, time: now - offset), current)
        }
        scheduledDeadlines = [:]
        scheduleFlushes()
    }

    /// call with `lock` held.
    private func configure(_ current: Settings) {
        if recognizer.tuning != current.tuning { recognizer.tuning = current.tuning }
        // waiting for an unmapped double tap would just delay a mapped single tap.
        let doubles: Set<Gesture> = [.threeFingerDoubleTap, .fourFingerDoubleTap, .fiveFingerDoubleTap]
        let awaited = current.previewing ? doubles : doubles.intersection(current.bindings.keys)
        if recognizer.awaitedDoubleTaps != awaited { recognizer.awaitedDoubleTaps = awaited }
    }

    /// call with `lock` held.
    private func scheduleFlushes() {
        for (device, deadline) in recognizer.pendingDeadlines() where scheduledDeadlines[device] != deadline {
            scheduledDeadlines[device] = deadline
            let wall = deadline + (clockOffsets[device] ?? 0)
            let delay = max(0, wall - ProcessInfo.processInfo.systemUptime) + 0.005
            timerQueue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.flushDue() }
        }
    }

    /// call with `lock` held.
    private func deliver(_ results: [RecognitionEvent], _ current: Settings) {
        for result in results {
            let event: Event
            switch result {
            case .recognized(let gesture):
                let shortcut = current.bindings[gesture]
                let send = current.enabled && !current.previewing && shortcut != nil
                if send, let shortcut { ShortcutSender.send(shortcut) }
                event = Event(gesture: gesture, recognized: true,
                              detail: shortcut?.text ?? String(localized: "eşleme yok"), sent: send)
                let line = "[gesture] \(gesture.rawValue) → \(event.detail)" + (send || shortcut == nil ? "" : " (not sent)")
                if current.debug { logger.emit(line) } else { Self.log.notice("\(line, privacy: .public)") }
            case .rejected(let gesture, let reason):
                event = Event(gesture: gesture, recognized: false, detail: reason.text, sent: false)
                if current.debug { logger.emit("[gesture] \(gesture.rawValue) rejected: \(reason.text)") }
            }
            eventHandler.withLock { $0 }?(event)
        }
    }
}
