import Foundation

/// gestures we can recognize. raw values are the keys in the config file.
public enum Gesture: String, Sendable, CaseIterable, Codable, Identifiable {
    case threeFingerTap
    case fourFingerTap
    case fiveFingerTap
    case threeFingerDoubleTap
    case fourFingerDoubleTap
    case fiveFingerDoubleTap
    case threeFingerHold
    /// one finger rests, one finger taps.
    case tipTapRight
    case tipTapLeft
    /// two fingers rest, one finger taps.
    case twoAnchorTipTapRight
    case twoAnchorTipTapLeft
    /// one finger rests, two fingers tap together.
    case twoFingerTipTapRight
    case twoFingerTipTapLeft
    case threeFingerSwipeLeft
    case threeFingerSwipeRight
    case threeFingerSwipeUp
    case threeFingerSwipeDown
    /// press the trackpad down (a physical click) while the fingers are on it.
    case threeFingerClick
    case fourFingerClick

    public var id: String { rawValue }

    /// the double-tap counterpart of an n-finger tap, if any.
    var doubleTap: Gesture? {
        switch self {
        case .threeFingerTap: .threeFingerDoubleTap
        case .fourFingerTap: .fourFingerDoubleTap
        case .fiveFingerTap: .fiveFingerDoubleTap
        default: nil
        }
    }
}

/// contents of ~/.config/better-gestures/config.json.
public struct GestureConfig: Sendable, Equatable, Codable {
    /// gesture name → shortcut text (e.g. "cmd+shift+]").
    public var gestures: [String: String]
    /// recognition thresholds; defaults are used if missing from the file or incomplete.
    public var tuning: RecognizerTuning

    public init(gestures: [String: String], tuning: RecognizerTuning = RecognizerTuning()) {
        self.gestures = gestures
        self.tuning = tuning
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gestures = try c.decode([String: String].self, forKey: .gestures)
        tuning = try c.decodeIfPresent(RecognizerTuning.self, forKey: .tuning) ?? RecognizerTuning()
    }

    /// unmapped gestures are still recognized and show up in the debug log as "no mapping".
    public static let `default` = GestureConfig(gestures: [
        Gesture.fourFingerTap.rawValue: "cmd+w",
        Gesture.tipTapRight.rawValue: "ctrl+tab",
        Gesture.tipTapLeft.rawValue: "ctrl+shift+tab",
    ])

    public struct Resolved: Sendable, Equatable {
        public var bindings: [Gesture: KeyShortcut]
        /// entries that couldn't be read; turned into text by the ui layer.
        public var warnings: [Warning]
    }

    public enum Warning: Sendable, Equatable, Hashable {
        case unknownGesture(String)
        case invalidShortcut(gesture: String, KeyShortcut.ParseError)
    }

    /// validates the texts and turns them into shortcuts; bad entries are skipped and returned as warnings.
    public func resolve() -> Resolved {
        var bindings: [Gesture: KeyShortcut] = [:]
        var warnings: [Warning] = []
        for (name, text) in gestures.sorted(by: { $0.key < $1.key }) {
            guard let gesture = Gesture(rawValue: name) else {
                warnings.append(.unknownGesture(name))
                continue
            }
            do {
                bindings[gesture] = try KeyShortcut(parsing: text)
            } catch {
                warnings.append(.invalidShortcut(gesture: name, error))
            }
        }
        return Resolved(bindings: bindings, warnings: warnings)
    }
}
