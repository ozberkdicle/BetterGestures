import Foundation
import GestureCore

/// ui (localized) text for the rejection reasons and warnings the core returns.

extension RejectionReason {
    var text: String {
        switch self {
        case .extraFingerLanded: String(localized: "fazladan parmak indi")
        case .anchorLifted: String(localized: "sabit parmak kalktı")
        case .anchorMoved(let value, let limit):
            String(localized: "sabit parmak kaydı \(Self.distance(value)) > \(Self.distance(limit))")
        case .tapperMoved(let value, let limit):
            String(localized: "dokunan parmak kaydı \(Self.distance(value)) > \(Self.distance(limit))")
        case .tooLong(let value, let limit):
            String(localized: "süre \(Self.duration(value)) > \(Self.duration(limit))")
        case .tappersOnBothSides: String(localized: "dokunan parmaklar sabitlerin iki yanında")
        case .moved(let value, let limit):
            String(localized: "kayma \(Self.distance(value)) > \(Self.distance(limit))")
        case .diagonal(let ratio, let limit):
            String(localized: "çapraz: yan/ana oran \(Self.ratio(ratio)) > \(Self.ratio(limit))")
        case .fingersDisagree(let weakest, let needed):
            String(localized: "parmaklar aynı yöne gitmiyor: \(Self.distance(weakest)) < \(Self.distance(needed))")
        }
    }

    /// normalized distance, as a percentage of the trackpad width.
    private static func distance(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    private static func duration(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }

    private static func ratio(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

extension GestureConfig.Warning {
    var text: String {
        switch self {
        case .unknownGesture(let name):
            String(localized: "Bilinmeyen jest: \(name)")
        case .invalidShortcut(let gesture, let error):
            "\(gesture): \(error.text)"
        }
    }
}

extension KeyShortcut.ParseError {
    var text: String {
        switch self {
        case .empty: String(localized: "boş kısayol")
        case .missingKey(let s): String(localized: "tuş yok: “\(s)”")
        case .unknownToken(let token): String(localized: "bilinmeyen tuş ya da değiştirici: “\(token)”")
        case .multipleKeys(let s): String(localized: "birden fazla tuş: “\(s)”")
        }
    }
}
