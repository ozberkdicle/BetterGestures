import Foundation
import GestureCore
import MultitouchBridge

/// passes every frame from every connected trackpad to `handler`.
/// `handler` runs under the bridge's lock, serially but not on a fixed thread.
final class TouchSource: @unchecked Sendable {
    struct Device: Sendable, Identifiable, Equatable {
        var id: UInt64
        var familyID: Int
        var builtIn: Bool
        /// mm
        var width: Double
        var height: Double

        var name: String { builtIn ? String(localized: "Dahili trackpad") : "Magic Trackpad" }
    }

    private let handler: @Sendable (TouchFrame) -> Void
    private(set) var isListening = false

    init(handler: @escaping @Sendable (TouchFrame) -> Void) {
        self.handler = handler
    }

    static var isSupported: Bool { MTBIsAvailable() }

    /// called on the main queue when a device is plugged or unplugged. set it once.
    func observeDeviceChanges(_ onChange: @escaping @MainActor () -> Void) {
        let box = Unmanaged.passRetained(ChangeBox(onChange)).toOpaque()
        MTBObserveDeviceChanges({ context in
            let box = Unmanaged<ChangeBox>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { box.onChange() }
        }, box)
    }

    /// call from the main thread. if already listening, rescans the device list.
    @discardableResult
    func start() -> [Device] {
        let context = Unmanaged.passUnretained(self).toOpaque()
        MTBStart({ context, deviceID, touches, count, timestamp, frame in
            let source = Unmanaged<TouchSource>.fromOpaque(context!).takeUnretainedValue()
            let buffer = UnsafeBufferPointer(start: touches, count: Int(count))
            source.handler(TouchFrame(
                timestamp: timestamp,
                frameID: Int(frame),
                deviceID: deviceID,
                touches: buffer.map(TouchSource.point)
            ))
        }, context)
        isListening = true
        return devices
    }

    func stop() {
        MTBStop()
        isListening = false
    }

    var devices: [Device] {
        var infos = [MTBDeviceInfo](repeating: MTBDeviceInfo(), count: 8)
        let count = Int(MTBGetDevices(&infos, Int32(infos.count)))
        return infos.prefix(count).map {
            Device(id: $0.deviceID, familyID: Int($0.familyID), builtIn: $0.builtIn,
                   width: Double($0.surfaceWidth) / 100, height: Double($0.surfaceHeight) / 100)
        }
    }

    private static func point(_ t: MTBTouch) -> TouchPoint {
        TouchPoint(
            id: Int(t.identifier),
            phase: TouchPoint.Phase(mtState: t.state),
            x: Double(t.x),
            y: Double(t.y),
            vx: Double(t.vx),
            vy: Double(t.vy),
            pressure: Double(t.pressure),
            majorAxis: Double(t.majorAxis),
            minorAxis: Double(t.minorAxis)
        )
    }

    private final class ChangeBox: @unchecked Sendable {
        let onChange: @MainActor () -> Void
        init(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    }
}

private extension TouchPoint.Phase {
    /// MTTouchState: 0 notTracking, 1 startInRange, 2 hoverInRange, 3 makeTouch,
    /// 4 touching, 5 breakTouch, 6 lingerInRange, 7 outOfRange.
    init(mtState: Int32) {
        switch mtState {
        case 1: self = .starting
        case 2: self = .hovering
        case 3: self = .making
        case 4: self = .touching
        case 5: self = .breaking
        case 6: self = .lingering
        case 7: self = .leaving
        default: self = .notTouching
        }
    }
}
