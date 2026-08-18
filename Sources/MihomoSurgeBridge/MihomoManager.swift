import Combine
import Darwin
import Foundation

enum MihomoProcessState: Equatable {
    case stopped
    case starting
    case running(pid: Int32)
    case failed(String)

    var label: String {
        switch self {
        case .stopped: "已停止"
        case .starting: "正在启动"
        case let .running(pid): "运行中（PID \(pid)）"
        case let .failed(message): "错误：\(message)"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

@MainActor
final class MihomoManager: ObservableObject {
    static let shared = MihomoManager()

    @Published private(set) var state: MihomoProcessState = .stopped
    private var process: Process?
    private var logHandle: FileHandle?

    private init() { }

    func validate(executable: URL, config: URL) async throws -> String {
        let result = try await Task.detached(priority: .userInitiated) {
            try ProcessRunner.run(executable, arguments: ["-t", "-f", config.path])
        }.value
        guard result.status == 0 else {
            throw MihomoManagerError.validation(Self.sanitize(result.output))
        }
        return result.output
    }

    func start(executable: URL, config: URL, runtime: URL, logURL: URL) async throws {
        if state.isRunning { return }
        state = .starting
        var openedHandle: FileHandle?
        do {
            _ = try await validate(executable: executable, config: config)

            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: logURL)
            openedHandle = handle
            try handle.seekToEnd()
            let child = Process()
            child.executableURL = executable
            child.arguments = ["-d", runtime.path, "-f", config.path]
            child.standardOutput = handle
            child.standardError = handle
            child.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    guard let self, self.process === process else { return }
                    self.process = nil
                    try? self.logHandle?.close()
                    self.logHandle = nil
                    if process.terminationStatus == 0 || process.terminationReason == .uncaughtSignal {
                        self.state = .stopped
                    } else {
                        self.state = .failed("Mihomo 已退出（状态 \(process.terminationStatus)）")
                    }
                }
            }
            try child.run()
            process = child
            logHandle = handle
            state = .running(pid: child.processIdentifier)
        } catch {
            try? openedHandle?.close()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() async {
        guard let process else {
            state = .stopped
            return
        }
        if process.isRunning { process.terminate() }
        for _ in 0 ..< 30 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        self.process = nil
        try? logHandle?.close()
        logHandle = nil
        state = .stopped
    }

    func restart(executable: URL, config: URL, runtime: URL, logURL: URL) async throws {
        await stop()
        try await start(executable: executable, config: config, runtime: runtime, logURL: logURL)
    }

    func stopSynchronously() {
        guard let process, process.isRunning else { return }
        process.terminate()
        for _ in 0 ..< 10 where process.isRunning { usleep(100_000) }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }

    func cleanupOrphan(executable: URL, config: URL) async {
        let executablePath = executable.path
        let configPath = config.path
        await Task.detached {
            guard let result = try? ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/pgrep"),
                arguments: ["-f", configPath]
            ), result.status == 0 else { return }
            for line in result.output.split(whereSeparator: \.isNewline) {
                guard let pid = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)),
                      pid != getpid(),
                      let command = try? ProcessRunner.run(
                        URL(fileURLWithPath: "/bin/ps"),
                        arguments: ["-p", String(pid), "-o", "command="]
                      ),
                      command.output.contains(executablePath),
                      command.output.contains(configPath) else { continue }
                Darwin.kill(pid, SIGTERM)
            }
        }.value
    }

    private static func sanitize(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(800))
    }
}

enum MihomoManagerError: LocalizedError {
    case validation(String)

    var errorDescription: String? {
        switch self {
        case let .validation(message): "Mihomo 配置无效：\(message)"
        }
    }
}
