import Foundation
import MihomoSurgeBridgeCore

struct ConfigurationStore: Sendable {
    let url: URL

    func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(AppConfiguration.self, from: Data(contentsOf: url))
        guard configuration.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
        return configuration
    }

    func save(_ configuration: AppConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(configuration).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct CacheStore: Sendable {
    let paths: AppPaths

    func load(subscriptionID: UUID) throws -> Data? {
        let url = paths.cacheFile(for: subscriptionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func save(_ data: Data, subscriptionID: UUID) throws {
        try data.write(to: paths.cacheFile(for: subscriptionID), options: .atomic)
    }

    func remove(subscriptionID: UUID) throws {
        let url = paths.cacheFile(for: subscriptionID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum AtomicFiles {
    static func write(_ files: [URL: Data]) throws {
        for (url, data) in files {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
    }
}

enum StoreError: LocalizedError {
    case unsupportedSchema

    var errorDescription: String? { "配置文件版本不受支持" }
}

@MainActor
final class AppLogger {
    private let url: URL

    init(url: URL) { self.url = url }

    func log(_ message: String) {
        let sanitized = message.replacingOccurrences(
            of: #"https?://[^\s]+"#,
            with: "<URL 已隐藏>",
            options: .regularExpression
        )
        let timestamp = LogTimestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(sanitized)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch { }
    }
}
