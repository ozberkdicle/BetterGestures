import Foundation
import GestureCore

enum ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/better-gestures", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("config.json")

    /// read the file; if it's missing, write the default and return that.
    static func load() throws -> GestureConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try save(.default)
            return .default
        }
        return try JSONDecoder().decode(GestureConfig.self, from: Data(contentsOf: fileURL))
    }

    static let backupURL = directory.appendingPathComponent("config.json.bak")

    /// copy the current file to `config.json.bak` (overwrites the old backup).
    static func backup() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    static func save(_ config: GestureConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(config)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
    }
}
