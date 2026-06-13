import Foundation

public struct SettingsStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL = SettingsStore.defaultConfigURL()) {
        self.fileURL = fileURL
    }

    public static func defaultConfigURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("CFST Manager", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaults()
        }
        let data = try Data(contentsOf: fileURL)
        var settings = try JSONDecoder().decode(AppSettings.self, from: data)
        settings.normalize()
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
    }
}
