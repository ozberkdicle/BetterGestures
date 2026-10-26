import Foundation
import Testing
@testable import GestureCore

/// tiny script writer that mimics the trackpad's ~15ms frames.
private struct Script {
    var recognizer = GestureRecognizer()
    var time = 100.0
    var events: [RecognitionEvent] = []
    var device: UInt64 = 1

    /// sends the given contacts as a frame every 15ms for `duration`.
    mutating func hold(_ duration: Double, _ touches: TouchPoint...) {
        for _ in 0..<max(1, Int((duration / 0.015).rounded())) {
            frame(touches)
        }
    }

    mutating func frame(_ touches: [TouchPoint]) {
        events += recognizer.process(TouchFrame(timestamp: time, deviceID: device, touches: touches))
        time += 0.015
    }

    /// every finger lifts (empty frame).
    mutating func liftAll() { frame([]) }

    /// releases the pending single tap as if `after` seconds passed without a frame.
    mutating func flush(after: Double) {
        events += recognizer.flush(deviceID: device, time: time + after)
    }

    var recognized: [Gesture] {
        events.compactMap { if case .recognized(let g) = $0 { g } else { nil } }
    }

    var rejected: [Gesture] {
        events.compactMap { if case .rejected(let g, _) = $0 { g } else { nil } }
    }
}

private func touch(_ id: Int, _ x: Double, _ y: Double, _ phase: TouchPoint.Phase = .touching) -> TouchPoint {
    TouchPoint(id: id, phase: phase, x: x, y: y)
}

private let fourFingers = [touch(1, 0.2, 0.5), touch(2, 0.4, 0.6), touch(3, 0.6, 0.6), touch(4, 0.8, 0.5)]

struct FourFingerTapTests {
    @Test func quickStationaryTapIsRecognized() {
        var s = Script()
        s.frame(fourFingers)
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        s.liftAll()
        #expect(s.recognized == [.fourFingerTap])
    }

    @Test func staggeredLandingWithinLimitIsRecognized() {
        var s = Script()
        s.frame([fourFingers[0]])
        s.frame(Array(fourFingers[0...1]))
        s.frame(Array(fourFingers[0...2]))
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        s.frame(Array(fourFingers[2...3]))  // fingers lift one by one
        s.liftAll()
        #expect(s.recognized == [.fourFingerTap])
    }

    @Test func liftingThroughBreakingPhaseCountsAsLift() {
        var s = Script()
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        s.frame(fourFingers.map { var t = $0; t.phase = .breaking; return t })
        #expect(s.recognized == [.fourFingerTap])
    }

    @Test func holdingTooLongIsRejected() {
        var s = Script()
        s.hold(0.6, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.fourFingerTap])
    }

    @Test func movingIsRejected() {
        var s = Script()
        s.hold(0.05, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        s.hold(0.05, touch(1, 0.2, 0.6), touch(2, 0.4, 0.7), touch(3, 0.6, 0.7), touch(4, 0.8, 0.6))
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.fourFingerTap])
    }

    @Test func fiveFingerTapIsRecognized() {
        var s = Script()
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3], touch(5, 0.5, 0.1))
        s.liftAll()
        #expect(s.recognized == [.fiveFingerTap])
    }

    @Test func sixContactsAreIgnored() {
        var s = Script()
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3], touch(5, 0.5, 0.1), touch(6, 0.9, 0.1))
        s.liftAll()
        #expect(s.events.isEmpty)
    }

    @Test func hoveringContactsDoNotCount() {
        var s = Script()
        let palm = touch(9, 0.9, 0.05, .hovering)
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3], palm)
        s.hold(0.03, palm)  // palm edge still near; fingers lifted
        #expect(s.recognized == [.fourFingerTap])
    }
}

struct TipTapTests {
    let anchor = touch(1, 0.5, 0.5)

    @Test func tapRightOfRestingFinger() {
        var s = Script()
        s.hold(0.3, anchor)
        s.hold(0.1, anchor, touch(2, 0.7, 0.5))
        s.hold(0.1, anchor)
        #expect(s.recognized == [.tipTapRight])
    }

    @Test func tapLeftOfRestingFinger() {
        var s = Script()
        s.hold(0.3, anchor)
        s.hold(0.1, anchor, touch(2, 0.3, 0.55))
        s.hold(0.1, anchor)
        #expect(s.recognized == [.tipTapLeft])
    }

    @Test func repeatedTapsWhileAnchorRests() {
        var s = Script()
        s.hold(0.3, anchor)
        s.hold(0.1, anchor, touch(2, 0.7, 0.5))
        s.hold(0.1, anchor)
        s.hold(0.1, anchor, touch(3, 0.3, 0.5))
        s.hold(0.1, anchor)
        s.hold(0.1, anchor, touch(4, 0.7, 0.5))
        s.hold(0.1, anchor)
        s.liftAll()
        #expect(s.recognized == [.tipTapRight, .tipTapLeft, .tipTapRight])
    }

    @Test func liftingBothTogetherIsRejected() {
        // if the resting and tapping fingers lift in the same frame the intent is unclear; no trigger.
        var s = Script()
        s.hold(0.3, anchor)
        s.hold(0.1, anchor, touch(2, 0.7, 0.5))
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.tipTapRight])
    }

    @Test func simultaneousTwoFingerTapIsIgnored() {
        // the system's two-finger tap (secondary click); must not count as tiptap.
        var s = Script()
        s.frame([anchor])
        s.hold(0.1, anchor, touch(2, 0.7, 0.5))
        s.liftAll()
        #expect(s.events.isEmpty)
    }

    @Test func slowTapIsRejected() {
        var s = Script()
        s.hold(0.3, anchor)
        s.hold(0.5, anchor, touch(2, 0.7, 0.5))
        s.hold(0.1, anchor)
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.tipTapRight])
    }

    @Test func movingAnchorIsRejected() {
        // two-finger scroll: first finger rests, second lands, then both move together.
        var s = Script()
        s.hold(0.3, anchor)
        s.frame([anchor, touch(2, 0.7, 0.5)])
        s.frame([touch(1, 0.5, 0.55), touch(2, 0.7, 0.55)])
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.tipTapRight])
    }

    @Test func movingTapperIsRejected() {
        var s = Script()
        s.hold(0.3, anchor)
        s.frame([anchor, touch(2, 0.7, 0.5)])
        s.frame([anchor, touch(2, 0.8, 0.5)])
        s.hold(0.1, anchor)
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.tipTapRight])
    }

    @Test func anchorLiftingFirstIsRejected() {
        var s = Script()
        s.hold(0.3, anchor)
        s.hold(0.05, anchor, touch(2, 0.7, 0.5))
        s.hold(0.05, touch(2, 0.7, 0.5))
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.tipTapRight])
    }

    @Test func lateThirdFingerCancels() {
        // if the second tapping finger lands after the pair window, the tiptap is cancelled.
        var s = Script()
        s.hold(0.3, anchor)
        s.hold(0.1, anchor, touch(2, 0.7, 0.5))
        s.hold(0.05, anchor, touch(2, 0.7, 0.5), touch(3, 0.8, 0.5))
        s.hold(0.1, anchor)
        s.liftAll()
        #expect(s.recognized.isEmpty)
        // the session reached 3 fingers but lasted long because of the resting finger: the 3-finger tap is rejected too.
        #expect(s.rejected == [.tipTapRight, .threeFingerTap])
    }

    @Test func devicesAreTrackedSeparately() {
        // a finger resting on the built-in trackpad doesn't make a tiptap with a tap on the magic trackpad.
        var s = Script()
        s.device = 1
        s.hold(0.3, anchor)
        s.device = 2
        s.hold(0.1, touch(2, 0.7, 0.5))
        s.liftAll()
        s.device = 1
        s.hold(0.1, anchor)
        #expect(s.events.isEmpty)
    }
}

struct TuningConfigTests {
    @Test func partialTuningKeepsDefaults() throws {
        let json = #"{"gestures": {}, "tuning": {"tipTapMaxDuration": 0.5}}"#
        let config = try JSONDecoder().decode(GestureConfig.self, from: Data(json.utf8))
        var expected = RecognizerTuning()
        expected.tipTapMaxDuration = 0.5
        #expect(config.tuning == expected)
    }

    @Test func missingTuningUsesDefaults() throws {
        let json = #"{"gestures": {"fourFingerTap": "cmd+w"}}"#
        let config = try JSONDecoder().decode(GestureConfig.self, from: Data(json.utf8))
        #expect(config.tuning == RecognizerTuning())
    }

    @Test func tuningChangesOutcome() {
        var tuning = RecognizerTuning()
        tuning.tapMaxDuration = 1.0
        var s = Script(recognizer: GestureRecognizer(tuning: tuning))
        s.hold(0.6, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        s.liftAll()
        #expect(s.recognized == [.fourFingerTap])
    }
}

struct ThreeFingerTests {
    let start = [touch(1, 0.3, 0.5), touch(2, 0.5, 0.55), touch(3, 0.7, 0.5)]

    /// moves three fingers by (dx, dy) every frame for `steps` frames.
    fileprivate func move(_ s: inout Script, from touches: [TouchPoint], dx: [Double], dy: [Double], steps: Int) -> [TouchPoint] {
        var current = touches
        for _ in 0..<steps {
            for i in current.indices {
                current[i].x += dx[i]
                current[i].y += dy[i]
            }
            s.frame(current)
        }
        return current
    }

    fileprivate func swipe(dx: Double, dy: Double) -> Script {
        var s = Script()
        s.frame(start)
        let end = move(&s, from: start, dx: [dx, dx, dx], dy: [dy, dy, dy], steps: 12)
        s.frame(end)
        s.liftAll()
        return s
    }

    @Test func tapIsRecognized() {
        var s = Script()
        s.hold(0.1, start[0], start[1], start[2])
        s.liftAll()
        #expect(s.recognized == [.threeFingerTap])
    }

    @Test func swipesInAllDirections() {
        #expect(swipe(dx: -0.02, dy: 0).recognized == [.threeFingerSwipeLeft])
        #expect(swipe(dx: 0.02, dy: 0).recognized == [.threeFingerSwipeRight])
        #expect(swipe(dx: 0, dy: 0.02).recognized == [.threeFingerSwipeUp])
        #expect(swipe(dx: 0, dy: -0.02).recognized == [.threeFingerSwipeDown])
    }

    @Test func swipeFiresOnceAndSuppressesTap() {
        let s = swipe(dx: 0.02, dy: 0)  // 0.24 travel: twice the threshold
        #expect(s.events == [.recognized(.threeFingerSwipeRight)])
    }

    @Test func swipeFiresBeforeLift() {
        var s = Script()
        s.frame(start)
        _ = move(&s, from: start, dx: [0.02, 0.02, 0.02], dy: [0, 0, 0], steps: 7)
        #expect(s.recognized == [.threeFingerSwipeRight])
    }

    @Test func shortMovementIsNeitherSwipeNorTap() {
        let s = swipe(dx: 0.005, dy: 0)  // 0.06: too much for a tap, too little for a swipe
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.threeFingerTap])
    }

    @Test func diagonalIsRejected() {
        let s = swipe(dx: 0.02, dy: 0.018)
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.threeFingerSwipeRight])
    }

    @Test func pinchIsNotASwipe() {
        var s = Script()
        s.frame(start)
        _ = move(&s, from: start, dx: [0.01, 0, -0.01], dy: [0, -0.005, 0], steps: 12)
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(!s.rejected.contains(.threeFingerSwipeRight))
    }

    @Test func oneStationaryFingerIsRejected() {
        // two fingers move, one stays: the average passes the threshold but the fingers don't agree.
        var s = Script()
        s.frame(start)
        _ = move(&s, from: start, dx: [0.025, 0.025, 0], dy: [0, 0, 0], steps: 12)
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.threeFingerSwipeRight])
    }

    @Test func measuresFromThirdFingerLanding() {
        // the first two fingers move first; measuring starts when the third lands.
        var s = Script()
        s.frame(Array(start[0...1]))
        let two = move(&s, from: Array(start[0...1]), dx: [0.02, 0.02], dy: [0, 0], steps: 5)
        s.frame(two + [start[2]])
        _ = move(&s, from: two + [start[2]], dx: [0.005, 0.005, 0.005], dy: [0, 0, 0], steps: 5)
        #expect(s.recognized.isEmpty)
    }

    @Test func fourFingerSwipeIsNotAThreeFingerSwipe() {
        var s = Script()
        s.frame(fourFingers)
        _ = move(&s, from: fourFingers, dx: [0.02, 0.02, 0.02, 0.02], dy: [0, 0, 0, 0], steps: 12)
        s.liftAll()
        #expect(s.recognized.isEmpty)
        #expect(s.rejected == [.fourFingerTap])
    }
}

struct TipTapVariantTests {
    let left = touch(1, 0.4, 0.5)
    let right = touch(2, 0.5, 0.52)

    @Test func twoAnchorsTapRight() {
        var s = Script()
        s.hold(0.3, left, right)
        s.hold(0.1, left, right, touch(3, 0.7, 0.5))
        s.hold(0.1, left, right)
        #expect(s.recognized == [.twoAnchorTipTapRight])
    }

    @Test func twoAnchorsTapLeft() {
        var s = Script()
        s.hold(0.3, left, right)
        s.hold(0.1, left, right, touch(3, 0.2, 0.5))
        s.hold(0.1, left, right)
        #expect(s.recognized == [.twoAnchorTipTapLeft])
    }

    @Test func tapBetweenAnchorsIsRejected() {
        var s = Script()
        let a = touch(1, 0.3, 0.5), b = touch(2, 0.7, 0.5)
        s.hold(0.3, a, b)
        s.hold(0.1, a, b, touch(3, 0.5, 0.6))
        s.hold(0.1, a, b)
        #expect(s.recognized.isEmpty)
        #expect(s.rejected.count == 1)
    }

    @Test func quickTwoAnchorTapIsNotAlsoAThreeFingerTap() {
        var s = Script()
        s.hold(0.18, left, right)
        s.hold(0.05, left, right, touch(3, 0.7, 0.5))
        s.hold(0.03, left, right)
        s.liftAll()
        #expect(s.events == [.recognized(.twoAnchorTipTapRight)])
    }

    @Test func twoFingersTapTogether() {
        var s = Script()
        s.hold(0.3, left)
        s.hold(0.1, left, touch(2, 0.6, 0.5), touch(3, 0.7, 0.5))
        s.hold(0.1, left)
        #expect(s.recognized == [.twoFingerTipTapRight])
    }

    @Test func twoFingersLandingOneFrameApart() {
        var s = Script()
        s.hold(0.3, left)
        s.frame([left, touch(2, 0.2, 0.5)])
        s.hold(0.1, left, touch(2, 0.2, 0.5), touch(3, 0.1, 0.5))
        s.hold(0.1, left)
        #expect(s.recognized == [.twoFingerTipTapLeft])
    }

    @Test func tappersOnBothSidesAreRejected() {
        var s = Script()
        s.hold(0.3, left)
        s.hold(0.1, left, touch(2, 0.2, 0.5), touch(3, 0.7, 0.5))
        s.hold(0.1, left)
        #expect(s.recognized.isEmpty)
        #expect(s.rejected.count == 1)
    }
}

struct HoldTests {
    let three = [touch(1, 0.3, 0.5), touch(2, 0.5, 0.55), touch(3, 0.7, 0.5)]

    @Test func stillThreeFingersFireWhileHeld() {
        var s = Script()
        s.hold(0.6, three[0], three[1], three[2])
        #expect(s.recognized == [.threeFingerHold])
        s.hold(0.5, three[0], three[1], three[2])
        s.liftAll()
        #expect(s.events == [.recognized(.threeFingerHold)])
    }

    @Test func shortHoldIsATap() {
        var s = Script()
        s.hold(0.2, three[0], three[1], three[2])
        s.liftAll()
        #expect(s.recognized == [.threeFingerTap])
    }

    @Test func movingFingersDoNotHold() {
        var s = Script()
        var current = three
        for _ in 0..<40 {
            for i in current.indices { current[i].x += 0.0015 }
            s.frame(current)
        }
        s.liftAll()
        #expect(!s.recognized.contains(.threeFingerHold))
    }
}

struct ClickTests {
    let three = [touch(1, 0.3, 0.5), touch(2, 0.5, 0.55), touch(3, 0.7, 0.5)]

    @Test func threeFingerClickReplacesTap() {
        var s = Script()
        s.hold(0.1, three[0], three[1], three[2])
        #expect(s.recognizer.click() == [.recognized(.threeFingerClick)])
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        #expect(s.events.isEmpty)  // same session doesn't count as a 3-finger tap
    }

    @Test func fourFingerClick() {
        var s = Script()
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        #expect(s.recognizer.click() == [.recognized(.fourFingerClick)])
    }

    @Test func otherFingerCountsAreNormalClicks() {
        var s = Script()
        #expect(s.recognizer.click().isEmpty)
        s.hold(0.1, three[0], three[1])
        #expect(s.recognizer.click().isEmpty)
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3], touch(5, 0.5, 0.1))
        #expect(s.recognizer.click().isEmpty)
    }

    @Test func clickPreventsLaterHold() {
        var s = Script()
        s.hold(0.1, three[0], three[1], three[2])
        _ = s.recognizer.click()
        s.hold(0.8, three[0], three[1], three[2])
        s.liftAll()
        #expect(s.events.isEmpty)
    }

    @Test func clickUsesDeviceWithFingers() {
        var s = Script()
        s.device = 2
        s.hold(0.1, touch(1, 0.5, 0.5))
        s.device = 1
        s.hold(0.1, three[0], three[1], three[2])
        #expect(s.recognizer.click() == [.recognized(.threeFingerClick)])
    }

    @Test func clickCancelsTipTapCandidate() {
        var s = Script()
        s.hold(0.3, three[0], three[1])
        s.frame([three[0], three[1], three[2]])  // two resting + one tapping: tiptap candidate
        _ = s.recognizer.click()
        s.frame([three[0], three[1]])
        s.liftAll()
        #expect(s.events.isEmpty)
    }
}

struct DoubleTapTests {
    let three = [touch(1, 0.3, 0.5), touch(2, 0.5, 0.55), touch(3, 0.7, 0.5)]

    fileprivate func script() -> Script {
        var s = Script()
        s.recognizer.awaitedDoubleTaps = [.threeFingerDoubleTap]
        return s
    }

    @Test func twoQuickTapsAreADoubleTap() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        #expect(s.events.isEmpty)  // waiting for the second tap
        s.time += 0.1
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        #expect(s.events == [.recognized(.threeFingerDoubleTap)])
    }

    @Test func singleTapIsReleasedAfterWindow() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        #expect(!s.recognizer.pendingDeadlines().isEmpty)
        s.flush(after: 0.1)
        #expect(s.events.isEmpty)
        s.flush(after: 0.3)
        #expect(s.events == [.recognized(.threeFingerTap)])
        #expect(s.recognizer.pendingDeadlines().isEmpty)
    }

    @Test func slowSecondTapGivesTwoSingles() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        s.time += 0.5
        s.hold(0.1, three[0], three[1], three[2])
        #expect(s.recognized == [.threeFingerTap])  // the first one is released as the second starts
        s.liftAll()
        s.flush(after: 0.3)
        #expect(s.recognized == [.threeFingerTap, .threeFingerTap])
    }

    @Test func flushWaitsForSecondTapInProgress() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        s.time += 0.1
        s.hold(0.1, three[0], three[1], three[2])
        s.flush(after: 0.3)  // second tap still in progress
        #expect(s.events.isEmpty)
        s.liftAll()
        #expect(s.events == [.recognized(.threeFingerDoubleTap)])
    }

    @Test func otherGestureReleasesPendingTap() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        s.time += 0.1
        s.hold(0.1, fourFingers[0], fourFingers[1], fourFingers[2], fourFingers[3])
        s.liftAll()
        #expect(s.recognized == [.threeFingerTap, .fourFingerTap])
    }

    @Test func fiveFingerDoubleTap() {
        let five = fourFingers + [touch(5, 0.5, 0.1)]
        var s = Script()
        s.recognizer.awaitedDoubleTaps = [.fiveFingerDoubleTap]
        s.hold(0.1, five[0], five[1], five[2], five[3], five[4])
        s.liftAll()
        s.time += 0.1
        s.hold(0.1, five[0], five[1], five[2], five[3], five[4])
        s.liftAll()
        #expect(s.events == [.recognized(.fiveFingerDoubleTap)])
    }

    @Test func movingSecondTouchReleasesPendingTapAtOnce() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        s.time += 0.1
        s.frame([touch(9, 0.5, 0.5)])
        #expect(s.recognizer.pendingDeadlines().isEmpty)  // no timer while a session is in progress
        s.frame([touch(9, 0.6, 0.5)])  // moving the cursor
        #expect(s.recognized == [.threeFingerTap])  // before the finger lifts
    }

    @Test func pendingTapComesBeforeSwipeOfNextTouch() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        s.time += 0.1
        s.frame(three)
        s.frame(three.map { var t = $0; t.x -= 0.2; return t })
        #expect(s.recognized == [.threeFingerTap, .threeFingerSwipeLeft])
    }

    @Test func clickReleasesPendingTapFirst() {
        var s = script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        s.time += 0.1
        s.frame(three)
        #expect(s.recognizer.click() == [.recognized(.threeFingerTap), .recognized(.threeFingerClick)])
    }

    @Test func notAwaitedMeansNoDelay() {
        var s = Script()
        s.hold(0.1, three[0], three[1], three[2])
        s.liftAll()
        #expect(s.recognized == [.threeFingerTap])
    }
}
