import Foundation

/// state of one finger on the trackpad in one frame. independent of the framework.
public struct TouchPoint: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case notTouching, starting, hovering, making, touching, breaking, lingering, leaving
    }

    public var id: Int
    public var phase: Phase
    /// normalized position, 0...1. y grows upward.
    public var x: Double
    public var y: Double
    /// velocity as reported by the hardware (normalized units / s).
    public var vx: Double
    public var vy: Double
    public var pressure: Double
    public var majorAxis: Double
    public var minorAxis: Double

    public init(
        id: Int, phase: Phase, x: Double, y: Double, vx: Double = 0, vy: Double = 0,
        pressure: Double = 0, majorAxis: Double = 0, minorAxis: Double = 0
    ) {
        self.id = id
        self.phase = phase
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.pressure = pressure
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
    }
}

/// one frame from a trackpad. empty `touches` means every finger lifted.
public struct TouchFrame: Sendable, Equatable {
    /// monotonic seconds (the device's own timestamp).
    public var timestamp: Double
    public var frameID: Int
    /// the device that produced the frame (built-in trackpad, magic trackpad…).
    public var deviceID: UInt64
    public var touches: [TouchPoint]

    public init(timestamp: Double, frameID: Int = 0, deviceID: UInt64 = 0, touches: [TouchPoint]) {
        self.timestamp = timestamp
        self.frameID = frameID
        self.deviceID = deviceID
        self.touches = touches
    }
}
