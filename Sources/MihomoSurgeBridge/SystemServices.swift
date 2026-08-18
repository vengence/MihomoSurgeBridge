import CryptoKit
import Darwin
import Foundation
import MihomoSurgeBridgeCore

enum PortChecker {
    static func isAvailable(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func firstAvailable(startingAt start: UInt16 = 17_892) -> UInt16? {
        for candidate in Int(start) ... min(Int(start) + 500, Int(UInt16.max)) {
            let port = UInt16(candidate)
            if isAvailable(port) { return port }
        }
        return nil
    }
}

enum MihomoLocator {
    static func locate(source: MihomoSource, paths: AppPaths) -> URL? {
        switch source {
        case .managed:
            return executable(paths.managedMihomo)
        case .homebrew:
            return homebrew()
        case .automatic:
            return homebrew() ?? executable(paths.managedMihomo)
        }
    }

    static func homebrew() -> URL? {
        for path in ["/opt/homebrew/bin/mihomo", "/usr/local/bin/mihomo"] {
            if let result = executable(URL(fileURLWithPath: path)) { return result }
        }
        return nil
    }

    private static func executable(_ url: URL) -> URL? {
        FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}

struct ProcessResult: Sendable {
    var status: Int32
    var output: String
}

enum ProcessRunner {
    static func run(_ executable: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return .init(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

actor ManagedMihomoInstaller {
    private struct Release: Decodable {
        var tag_name: String
        var assets: [Asset]
    }

    private struct Asset: Decodable {
        var name: String
        var digest: String?
        var browser_download_url: URL
    }

    func install(to destination: URL) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest")!)
        request.setValue("MihomoSurgeBridge/1.0", forHTTPHeaderField: "User-Agent")
        let (metadata, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw InstallerError.releaseMetadata
        }
        let release = try JSONDecoder().decode(Release.self, from: metadata)
        guard let asset = release.assets.first(where: {
            $0.name.hasPrefix("mihomo-darwin-arm64-v") && $0.name.hasSuffix(".gz")
        }), let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw InstallerError.assetMissing
        }

        let (archive, archiveResponse) = try await URLSession.shared.data(from: asset.browser_download_url)
        guard let archiveHTTP = archiveResponse as? HTTPURLResponse,
              (200 ... 299).contains(archiveHTTP.statusCode),
              archive.count < 100 * 1_024 * 1_024 else {
            throw InstallerError.download
        }
        let actual = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard actual == String(digest.dropFirst("sha256:".count)).lowercased() else {
            throw InstallerError.checksum
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archiveURL = directory.appendingPathComponent("mihomo.download.gz")
        let temporary = directory.appendingPathComponent("mihomo.installing")
        try archive.write(to: archiveURL, options: .atomic)
        if FileManager.default.fileExists(atPath: temporary.path) {
            try FileManager.default.removeItem(at: temporary)
        }
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", archiveURL.path]
        process.standardOutput = handle
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: archiveURL)
        guard process.terminationStatus == 0 else { throw InstallerError.decompression }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        let result = try ProcessRunner.run(destination, arguments: ["-v"])
        guard result.status == 0 else { throw InstallerError.invalidExecutable }
        return "\(release.tag_name) · \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

enum InstallerError: LocalizedError {
    case releaseMetadata, assetMissing, download, checksum, decompression, invalidExecutable

    var errorDescription: String? {
        switch self {
        case .releaseMetadata: "无法读取 Mihomo 官方 Release 信息"
        case .assetMissing: "官方 Release 中没有标准 darwin-arm64 资产或 SHA-256"
        case .download: "Mihomo 下载失败"
        case .checksum: "Mihomo 官方 SHA-256 校验失败"
        case .decompression: "Mihomo 解压失败"
        case .invalidExecutable: "安装后的 Mihomo 无法运行"
        }
    }
}
