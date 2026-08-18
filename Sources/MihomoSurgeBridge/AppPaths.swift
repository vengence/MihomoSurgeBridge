import Foundation

struct AppPaths: Sendable {
    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let override = ProcessInfo.processInfo.environment["MIHOMO_SURGE_BRIDGE_DATA_DIR"], !override.isEmpty {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("MihomoSurgeBridge", isDirectory: true)
        }
    }

    var config: URL { root.appendingPathComponent("config.json") }
    var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    var core: URL { root.appendingPathComponent("Core", isDirectory: true) }
    var managedMihomo: URL { core.appendingPathComponent("mihomo") }
    var runtime: URL { root.appendingPathComponent("Runtime", isDirectory: true) }
    var runtimeConfig: URL { runtime.appendingPathComponent("mihomo.yaml") }
    var generated: URL { root.appendingPathComponent("Generated", isDirectory: true) }
    var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    var appLog: URL { logs.appendingPathComponent("app.log") }
    var mihomoLog: URL { logs.appendingPathComponent("mihomo.log") }

    func ensureDirectories() throws {
        for directory in [root, cache, core, runtime, generated, logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func cacheFile(for id: UUID) -> URL {
        cache.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("yaml")
    }
}
