import Foundation
import GestureCore
import os

/// prints raw frames to stdout and the unified log in debug mode.
/// only called from the TouchSource handler (serially), so no lock.
final class DebugLogger: @unchecked Sendable {
    static let subsystem = Bundle.main.bundleIdentifier ?? "dev.ozberk.BetterGestures"
    private static let log = Logger(subsystem: subsystem, category: "touch")

    /// short form of the device id, to match lines with the device list printed at startup.
    static func label(_ deviceID: UInt64) -> String {
        String(format: "%04x", deviceID & 0xffff)
    }

    private struct DeviceState {
        var previousTimestamp: Double?
        var previousFrameID: Int?
        var contactStart: Double?
        var contactFrames = 0
        var maxFingers = 0
    }

    private var states: [UInt64: DeviceState] = [:]

    func log(_ frame: TouchFrame) {
        var s = states[frame.deviceID, default: DeviceState()]
        defer { states[frame.deviceID] = s }

        let dt = s.previousTimestamp.map { (frame.timestamp - $0) * 1000 }
        let skipped = s.previousFrameID.map { frame.frameID - $0 - 1 } ?? 0
        s.previousTimestamp = frame.timestamp
        s.previousFrameID = frame.frameID
        let prefix = String(format: "[%10.4f] %@ #%d", frame.timestamp, Self.label(frame.deviceID), frame.frameID)

        if frame.touches.isEmpty {
            // the device sends a few empty frames after fingers lift; only print the first.
            guard let start = s.contactStart else { return }
            emit(String(format: "%@  -- lifted: duration=%.0fms frames=%d maxFingers=%d",
                        prefix, (frame.timestamp - start) * 1000, s.contactFrames, s.maxFingers))
            s.contactStart = nil
            s.contactFrames = 0
            s.maxFingers = 0
            return
        }

        if s.contactStart == nil { s.contactStart = frame.timestamp }
        s.contactFrames += 1
        s.maxFingers = max(s.maxFingers, frame.touches.count)

        var line = prefix + String(format: " dt=%5.1fms n=%d", dt ?? 0, frame.touches.count)
        if skipped > 0 { line += " SKIPPED=\(skipped)" }
        for t in frame.touches.sorted(by: { $0.id < $1.id }) {
            line += String(format: " | id=%d %@ pos(%.3f,%.3f) v(%+.2f,%+.2f) p=%.1f",
                           t.id, t.phase.rawValue, t.x, t.y, t.vx, t.vy, t.pressure)
        }
        emit(line)
    }

    func emit(_ line: String) {
        print(line)
        Self.log.info("\(line, privacy: .public)")
    }
}
