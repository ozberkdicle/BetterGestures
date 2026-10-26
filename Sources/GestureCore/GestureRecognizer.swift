import Foundation

/// an event the recognizer produced for one frame. `rejected` shows up in the debug log, for tuning.
public enum RecognitionEvent: Sendable, Equatable {
    case recognized(Gesture)
    case rejected(Gesture, reason: RejectionReason)
}

/// why a gesture wasn't recognized. turned into text by the ui layer.
/// distances are normalized, times are seconds; `limit` is the threshold that was exceeded.
public enum RejectionReason: Sendable, Equatable {
    /// an unexpected extra finger landed during a tiptap.
    case extraFingerLanded
    case anchorLifted
    case anchorMoved(Double, limit: Double)
    case tapperMoved(Double, limit: Double)
    /// the tap or tiptap took too long.
    case tooLong(Double, limit: Double)
    /// tapping fingers are on both sides of the resting fingers; direction is unclear.
    case tappersOnBothSides
    /// a finger moved too far during a tap.
    case moved(Double, limit: Double)
    /// swipe was diagonal: cross axis / main axis ratio.
    case diagonal(ratio: Double, limit: Double)
    /// fingers didn't move the same way during a swipe (pinch, rotate).
    case fingersDisagree(weakest: Double, needed: Double)
}

/// thresholds. distances are normalized (trackpad width/height = 1), times are seconds.
public struct RecognizerTuning: Sendable, Equatable, Codable {
    /// 3/4/5-finger tap: max time from the first finger landing to the last one lifting.
    public var tapMaxDuration = 0.35
    /// 3/4/5-finger tap: max distance any finger moves from where it landed.
    public var tapMaxMovement = 0.03
    /// double tap: max gap between the end of the first tap and the start of the second.
    /// if a double tap is mapped, the single tap is delayed by this much.
    public var doubleTapWindow = 0.25
    /// 3-finger hold: how long the fingers have to stay still to trigger.
    public var holdDuration = 0.5
    /// 3-finger hold: max movement of any finger.
    public var holdMaxMovement = 0.03
    /// tiptap: the resting finger(s) must be down at least this long before the other lands.
    /// tells it apart from fingers tapping together (e.g. the system's secondary click).
    public var tipTapAnchorMinHold = 0.15
    /// tiptap: max movement of the resting fingers during the tap.
    public var tipTapAnchorMaxMovement = 0.02
    /// tiptap: max time the tapping finger(s) stay down.
    public var tipTapMaxDuration = 0.30
    /// tiptap: max movement of the tapping finger(s).
    public var tipTapMaxMovement = 0.03
    /// two-finger tiptap: the second tapping finger has to land at most this long after the first.
    public var tipTapPairWindow = 0.08
    /// 3-finger swipe: fires once the fingers' average travel passes this distance.
    public var swipeMinDistance = 0.12
    /// 3-finger swipe: max ratio of cross-axis to main-axis movement (rejects diagonal swipes).
    public var swipeMaxOffAxisRatio = 0.6
    /// 3-finger swipe: every finger has to move at least this share of the average the same way
    /// (rejects pinch/rotate).
    public var swipeMinFingerAgreement = 0.5

    public init() {}

    /// missing fields keep their defaults, so the config can hold only the thresholds that changed.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var t = RecognizerTuning()
        func read(_ key: CodingKeys, _ path: WritableKeyPath<RecognizerTuning, Double>) throws {
            if let value = try c.decodeIfPresent(Double.self, forKey: key) { t[keyPath: path] = value }
        }
        try read(.tapMaxDuration, \.tapMaxDuration)
        try read(.tapMaxMovement, \.tapMaxMovement)
        try read(.doubleTapWindow, \.doubleTapWindow)
        try read(.holdDuration, \.holdDuration)
        try read(.holdMaxMovement, \.holdMaxMovement)
        try read(.tipTapAnchorMinHold, \.tipTapAnchorMinHold)
        try read(.tipTapAnchorMaxMovement, \.tipTapAnchorMaxMovement)
        try read(.tipTapMaxDuration, \.tipTapMaxDuration)
        try read(.tipTapMaxMovement, \.tipTapMaxMovement)
        try read(.tipTapPairWindow, \.tipTapPairWindow)
        try read(.swipeMinDistance, \.swipeMinDistance)
        try read(.swipeMaxOffAxisRatio, \.swipeMaxOffAxisRatio)
        try read(.swipeMinFingerAgreement, \.swipeMinFingerAgreement)
        self = t
    }
}

/// pure state machine that turns touch frames into gestures. each device is tracked separately.
///
/// only contacts in the `making`/`touching` phase count as "down"; `starting`/`hovering`
/// (approaching finger, palm edge) and `breaking`/`lingering`/`leaving` (lifting finger) don't.
/// a contact that's missing from a frame counts as lifted too.
///
/// session: from the moment the pressed finger count leaves 0 until it's back at 0. if a tiptap,
/// hold or swipe is recognized in a session, no tap is looked for at its end.
public struct GestureRecognizer: Sendable {
    public var tuning: RecognizerTuning
    /// double taps to wait for. if one is in here, its single tap is held for `doubleTapWindow`;
    /// otherwise the single tap is reported right away. the app passes the mapped double taps.
    public var awaitedDoubleTaps: Set<Gesture> = []
    private var devices: [UInt64: DeviceState] = [:]

    public init(tuning: RecognizerTuning = RecognizerTuning()) {
        self.tuning = tuning
    }

    public mutating func reset() {
        devices = [:]
    }

    public mutating func process(_ frame: TouchFrame) -> [RecognitionEvent] {
        var state = devices[frame.deviceID, default: DeviceState()]
        let events = state.process(frame, tuning: tuning, awaited: awaitedDoubleTaps)
        devices[frame.deviceID] = state
        return events
    }

    /// when a pending single tap expires (device clock) if the second tap never came. the trackpad
    /// stops sending frames once fingers lift, so `flush` has to be called at that time.
    /// no timer while a session is in progress: that session's frames settle the pending tap.
    public func pendingDeadlines() -> [UInt64: Double] {
        devices.compactMapValues { state in
            guard state.sessionStart == nil else { return nil }
            return state.pendingTap.map { $0.end + tuning.doubleTapWindow }
        }
    }

    /// the trackpad was physically clicked. the click event doesn't say which device, so the one with
    /// the most fingers down wins. with 3 or 4 fingers down the click gesture is recognized and the
    /// rest of the session produces nothing else; otherwise empty (a normal click). the click gesture
    /// is always last; a single tap held for a double tap may be released before it.
    public mutating func click() -> [RecognitionEvent] {
        guard let (id, state) = devices.max(by: { $0.value.contacts.count < $1.value.contacts.count })
        else { return [] }
        var updated = state
        let events = updated.click()
        devices[id] = updated
        return events
    }

    /// reports a pending single tap whose time is up. `time` is on the device clock.
    public mutating func flush(deviceID: UInt64, time: Double) -> [RecognitionEvent] {
        guard var state = devices[deviceID] else { return [] }
        let events = state.flush(time: time, tuning: tuning)
        devices[deviceID] = state
        return events
    }
}

private struct Contact: Sendable {
    var landTime: Double
    var landX: Double
    var landY: Double
    var x: Double
    var y: Double
    var maxDisplacement = 0.0

    init(time: Double, x: Double, y: Double) {
        landTime = time
        landX = x
        landY = y
        self.x = x
        self.y = y
    }

    mutating func move(x: Double, y: Double) {
        self.x = x
        self.y = y
        maxDisplacement = max(maxDisplacement, hypot(x - landX, y - landY))
    }
}

/// tiptap candidate: tapping finger(s) landed while the resting one(s) are down, waiting for them to lift.
private struct TipTapCandidate: Sendable {
    var anchorIDs: Set<Int>
    var tapperIDs: Set<Int>
    var liftedTappers: Set<Int> = []
    var startTime: Double
    /// positions of the resting fingers when the tap started.
    var anchorStart: [Int: Point]
    /// where the tapping fingers landed (x).
    var tapperX: [Int: Double]

    struct Point: Sendable { var x, y: Double }

    /// right if every tapping finger is right of the resting ones, left if all are left; nil in between.
    var side: Bool? {
        let anchors = anchorStart.values.map(\.x)
        let tappers = tapperX.values
        if tappers.allSatisfy({ $0 > anchors.max()! }) { return true }
        if tappers.allSatisfy({ $0 < anchors.min()! }) { return false }
        return nil
    }

    /// gesture to show when rejecting: if the side is unclear, guess from the averages.
    var bestGuess: Gesture {
        let right = side ?? (tapperX.values.reduce(0, +) / Double(tapperX.count)
            >= anchorStart.values.map(\.x).reduce(0, +) / Double(anchorStart.count))
        return Self.gesture(anchors: anchorIDs.count, tappers: tapperIDs.count, right: right)
    }

    static func gesture(anchors: Int, tappers: Int, right: Bool) -> Gesture {
        switch (anchors, tappers) {
        case (2, _): right ? .twoAnchorTipTapRight : .twoAnchorTipTapLeft
        case (_, 2): right ? .twoFingerTipTapRight : .twoFingerTipTapLeft
        default: right ? .tipTapRight : .tipTapLeft
        }
    }
}

/// swipe/hold measured from the positions at the moment the third finger lands, with exactly three down.
private struct ThreeFingerTracker: Sendable {
    var ids: Set<Int>
    var startTime: Double
    var startX: [Int: Double]
    var startY: [Int: Double]
}

/// a single tap held back for a possible double tap.
private struct PendingTap: Sendable {
    var gesture: Gesture
    /// when the first tap ended.
    var end: Double
    var fingers: Int
}

private struct DeviceState: Sendable {
    var contacts: [Int: Contact] = [:]
    var tipTap: TipTapCandidate?
    var three: ThreeFingerTracker?
    var pendingTap: PendingTap?

    var sessionStart: Double?
    var sessionMaxFingers = 0
    var sessionMaxMovement = 0.0
    /// a non-tap gesture was decided in this session (tiptap, hold, swipe).
    var sessionConsumed = false
    /// a click gesture was recognized in this session; no tiptap either until it ends.
    var sessionClicked = false

    mutating func process(_ frame: TouchFrame, tuning: RecognizerTuning, awaited: Set<Gesture>) -> [RecognitionEvent] {
        let now = frame.timestamp
        let active = frame.touches.filter { $0.phase == .making || $0.phase == .touching }
        let activeIDs = Set(active.map(\.id))
        let landed = active.filter { contacts[$0.id] == nil }
        let lifted = Set(contacts.keys).subtracting(activeIDs)
        var events: [RecognitionEvent] = []

        // a new session started after the double-tap window closed: release the pending single tap.
        if sessionStart == nil, !activeIDs.isEmpty {
            events += flush(time: now, tuning: tuning)
        }
        let gestureEventsStart = events.count

        for t in active {
            contacts[t.id, default: Contact(time: now, x: t.x, y: t.y)].move(x: t.x, y: t.y)
        }

        if let event = advanceTipTap(landed: landed, lifted: lifted, now: now, tuning: tuning) {
            events.append(event)
        }
        if tipTap == nil {
            beginTipTap(landed: landed, activeIDs: activeIDs, now: now, tuning: tuning)
        }
        if let event = advanceThreeFingers(activeIDs: activeIDs, now: now, tuning: tuning) {
            events.append(event)
        }

        if !activeIDs.isEmpty {
            if sessionStart == nil { sessionStart = now }
            sessionMaxFingers = max(sessionMaxFingers, activeIDs.count)
            sessionMaxMovement = max(sessionMaxMovement, activeIDs.map { contacts[$0]!.maxDisplacement }.max()!)
        }

        // if this session can't turn into the same tap anymore, release the pending single tap now:
        // don't make it wait for the session to end, and let it come before this frame's gesture.
        if let pending = pendingTap, let start = sessionStart, !activeIDs.isEmpty,
           sessionConsumed || sessionMaxFingers > pending.fingers || now - start > tuning.tapMaxDuration
            || sessionMaxMovement > tuning.tapMaxMovement {
            pendingTap = nil
            events.insert(.recognized(pending.gesture), at: gestureEventsStart)
        }

        for id in lifted { contacts[id] = nil }

        if activeIDs.isEmpty, let start = sessionStart {
            let tap = sessionConsumed ? nil : tapResult(duration: now - start, tuning: tuning)
            events += resolveTap(tap, sessionStart: start, now: now, tuning: tuning, awaited: awaited)
            sessionStart = nil
            sessionMaxFingers = 0
            sessionMaxMovement = 0
            sessionConsumed = false
            sessionClicked = false
        }
        return events
    }

    mutating func click() -> [RecognitionEvent] {
        let gesture: Gesture
        switch contacts.count {
        case 3: gesture = .threeFingerClick
        case 4: gesture = .fourFingerClick
        default: return []
        }
        var events: [RecognitionEvent] = []
        if let pending = pendingTap {
            pendingTap = nil
            events.append(.recognized(pending.gesture))
        }
        sessionConsumed = true
        sessionClicked = true
        tipTap = nil
        events.append(.recognized(gesture))
        return events
    }

    mutating func flush(time: Double, tuning: RecognizerTuning) -> [RecognitionEvent] {
        // a session that started inside the window may still be a double tap; wait for it to end.
        guard let pending = pendingTap, time - pending.end > tuning.doubleTapWindow, sessionStart == nil
        else { return [] }
        pendingTap = nil
        return [.recognized(pending.gesture)]
    }

    // MARK: - tiptap

    /// settles or continues the pending tiptap candidate based on what happened this frame.
    private mutating func advanceTipTap(
        landed: [TouchPoint], lifted: Set<Int>, now: Double, tuning: RecognizerTuning
    ) -> RecognitionEvent? {
        guard var c = tipTap else { return nil }

        if !landed.isEmpty {
            // with a single resting finger, a second tapping finger may land right after the first.
            let canPair = c.anchorIDs.count == 1 && c.tapperIDs.count == 1 && landed.count == 1
                && c.liftedTappers.isEmpty && now - c.startTime <= tuning.tipTapPairWindow
            guard canPair else { return reject(c, .extraFingerLanded) }
            c.tapperIDs.insert(landed[0].id)
            c.tapperX[landed[0].id] = landed[0].x
        }
        if !lifted.isDisjoint(with: c.anchorIDs) {
            return reject(c, .anchorLifted)
        }
        let anchorMovement = c.anchorStart.map { id, p in
            contacts[id].map { hypot($0.x - p.x, $0.y - p.y) } ?? 0
        }.max() ?? 0
        if anchorMovement > tuning.tipTapAnchorMaxMovement {
            return reject(c, .anchorMoved(anchorMovement, limit: tuning.tipTapAnchorMaxMovement))
        }
        let tapperMovement = c.tapperIDs.map { contacts[$0]?.maxDisplacement ?? 0 }.max() ?? 0
        if tapperMovement > tuning.tipTapMaxMovement {
            return reject(c, .tapperMoved(tapperMovement, limit: tuning.tipTapMaxMovement))
        }

        c.liftedTappers.formUnion(lifted.intersection(c.tapperIDs))
        guard c.liftedTappers == c.tapperIDs else {
            tipTap = c  // tapping finger(s) still down
            return nil
        }
        let duration = now - c.startTime
        if duration > tuning.tipTapMaxDuration {
            return reject(c, .tooLong(duration, limit: tuning.tipTapMaxDuration))
        }
        guard let right = c.side else {
            return reject(c, .tappersOnBothSides)
        }
        tipTap = nil
        sessionConsumed = true
        return .recognized(TipTapCandidate.gesture(anchors: c.anchorIDs.count, tappers: c.tapperIDs.count, right: right))
    }

    private mutating func reject(_ c: TipTapCandidate, _ reason: RejectionReason) -> RecognitionEvent {
        tipTap = nil
        return .rejected(c.bestGuess, reason: reason)
    }

    /// starts a tiptap candidate when new finger(s) land while one or two fingers have been down long
    /// enough. if the resting ones weren't down long enough, quietly skip: that happens on every
    /// multi-finger scroll.
    private mutating func beginTipTap(landed: [TouchPoint], activeIDs: Set<Int>, now: Double, tuning: RecognizerTuning) {
        let tapperIDs = Set(landed.map(\.id))
        let anchorIDs = activeIDs.subtracting(tapperIDs)
        guard !sessionClicked, !landed.isEmpty, (1...2).contains(anchorIDs.count), anchorIDs.count + landed.count <= 3,
              anchorIDs.allSatisfy({ now - contacts[$0]!.landTime >= tuning.tipTapAnchorMinHold })
        else { return }

        tipTap = TipTapCandidate(
            anchorIDs: anchorIDs, tapperIDs: tapperIDs, startTime: now,
            anchorStart: anchorIDs.reduce(into: [:]) { $0[$1] = .init(x: contacts[$1]!.x, y: contacts[$1]!.y) },
            tapperX: landed.reduce(into: [:]) { $0[$1.id] = $1.x }
        )
    }

    // MARK: - 3 fingers: swipe and hold

    /// tracks distance and time while exactly three fingers are down; one decision per session.
    /// if the set of fingers changes (one lifts or lands) measuring restarts from the new positions.
    private mutating func advanceThreeFingers(activeIDs: Set<Int>, now: Double, tuning: RecognizerTuning) -> RecognitionEvent? {
        guard activeIDs.count == 3 else {
            three = nil
            return nil
        }
        guard let tracker = three, tracker.ids == activeIDs else {
            three = ThreeFingerTracker(ids: activeIDs, startTime: now,
                                       startX: activeIDs.reduce(into: [:]) { $0[$1] = contacts[$1]!.x },
                                       startY: activeIDs.reduce(into: [:]) { $0[$1] = contacts[$1]!.y })
            return nil
        }
        guard !sessionConsumed else { return nil }

        let moves = activeIDs.map { (dx: contacts[$0]!.x - tracker.startX[$0]!, dy: contacts[$0]!.y - tracker.startY[$0]!) }
        if let event = swipeResult(moves, tuning: tuning) {
            sessionConsumed = true
            return event
        }
        let movement = moves.map { hypot($0.dx, $0.dy) }.max()!
        if now - tracker.startTime >= tuning.holdDuration, movement <= tuning.holdMaxMovement {
            sessionConsumed = true
            tipTap = nil  // might have started as two resting + one tapping
            return .recognized(.threeFingerHold)
        }
        return nil
    }

    private func swipeResult(_ moves: [(dx: Double, dy: Double)], tuning: RecognizerTuning) -> RecognitionEvent? {
        let meanX = moves.map(\.dx).reduce(0, +) / 3
        let meanY = moves.map(\.dy).reduce(0, +) / 3
        let horizontal = abs(meanX) >= abs(meanY)
        let along = horizontal ? meanX : meanY
        let across = horizontal ? meanY : meanX
        guard abs(along) >= tuning.swipeMinDistance else { return nil }

        // y grows upward.
        let gesture: Gesture = horizontal
            ? (along < 0 ? .threeFingerSwipeLeft : .threeFingerSwipeRight)
            : (along > 0 ? .threeFingerSwipeUp : .threeFingerSwipeDown)

        if abs(across) > tuning.swipeMaxOffAxisRatio * abs(along) {
            return .rejected(gesture, reason: .diagonal(ratio: abs(across) / abs(along), limit: tuning.swipeMaxOffAxisRatio))
        }
        let weakest = moves.map { (horizontal ? $0.dx : $0.dy) * (along < 0 ? -1 : 1) }.min()!
        if weakest < tuning.swipeMinFingerAgreement * abs(along) {
            return .rejected(gesture, reason: .fingersDisagree(
                weakest: weakest, needed: tuning.swipeMinFingerAgreement * abs(along)))
        }
        return .recognized(gesture)
    }

    // MARK: - tap and double tap

    /// at the end of a session: was it a short, still tap with 3, 4 or 5 fingers?
    private func tapResult(duration: Double, tuning: RecognizerTuning) -> RecognitionEvent? {
        let gesture: Gesture
        switch sessionMaxFingers {
        case 3: gesture = .threeFingerTap
        case 4: gesture = .fourFingerTap
        case 5: gesture = .fiveFingerTap
        default: return nil
        }
        if duration > tuning.tapMaxDuration {
            return .rejected(gesture, reason: .tooLong(duration, limit: tuning.tapMaxDuration))
        }
        if sessionMaxMovement > tuning.tapMaxMovement {
            return .rejected(gesture, reason: .moved(sessionMaxMovement, limit: tuning.tapMaxMovement))
        }
        return .recognized(gesture)
    }

    /// end of session: pairs the tap with a pending single tap (double tap), or holds it back if needed.
    private mutating func resolveTap(
        _ tap: RecognitionEvent?, sessionStart: Double, now: Double, tuning: RecognizerTuning, awaited: Set<Gesture>
    ) -> [RecognitionEvent] {
        var events: [RecognitionEvent] = []
        if let pending = pendingTap {
            pendingTap = nil
            if case .recognized(let gesture)? = tap, gesture == pending.gesture,
               sessionStart - pending.end <= tuning.doubleTapWindow, let double = gesture.doubleTap {
                return [.recognized(double)]
            }
            events.append(.recognized(pending.gesture))
        }
        if case .recognized(let gesture)? = tap, let double = gesture.doubleTap, awaited.contains(double) {
            pendingTap = PendingTap(gesture: gesture, end: now, fingers: sessionMaxFingers)
            return events
        }
        if let tap { events.append(tap) }
        return events
    }
}
