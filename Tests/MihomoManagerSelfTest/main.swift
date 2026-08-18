import Foundation

struct ProcessRunResult: Sendable {
    let status: Int32
    let output: String
}

enum ProcessRunner {
    static func run(_ executable: URL, arguments: [String]) throws -> ProcessRunResult {
        if arguments.last?.contains("invalid") == true {
            return ProcessRunResult(status: 1, output: "测试配置无效")
        }
        return ProcessRunResult(status: 0, output: "测试配置有效")
    }
}

@main
@MainActor
struct MihomoManagerSelfTest {
    static func main() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoManagerSelfTest-\(UUID().uuidString)", isDirectory: true)
        let executable = root.appendingPathComponent("fake-mihomo")
        let validConfig = root.appendingPathComponent("valid.yaml")
        let invalidConfig = root.appendingPathComponent("invalid.yaml")
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let log = root.appendingPathComponent("mihomo.log")

        do {
            try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
            try Data("#!/bin/sh\nsleep 30\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            try Data("valid".utf8).write(to: validConfig)
            try Data("invalid".utf8).write(to: invalidConfig)

            let manager = MihomoManager.shared
            try await manager.start(
                executable: executable,
                config: validConfig,
                runtime: runtime,
                logURL: log
            )
            guard manager.state.isRunning else { throw TestError.notRunningAfterStart }

            _ = try await manager.validate(executable: executable, config: validConfig)
            guard manager.state.isRunning else { throw TestError.stateChangedAfterSuccessfulValidation }

            do {
                _ = try await manager.validate(executable: executable, config: invalidConfig)
                throw TestError.invalidValidationUnexpectedlyPassed
            } catch is MihomoManagerError {
                guard manager.state.isRunning else { throw TestError.stateChangedAfterFailedValidation }
            }

            await manager.stop()
            try? FileManager.default.removeItem(at: root)
            print("✓ 配置检查成功后保持运行状态")
            print("✓ 配置检查失败后保持运行状态")
        } catch {
            await MihomoManager.shared.stop()
            try? FileManager.default.removeItem(at: root)
            fputs("✗ Mihomo 状态回归测试失败：\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private enum TestError: LocalizedError {
    case notRunningAfterStart
    case stateChangedAfterSuccessfulValidation
    case stateChangedAfterFailedValidation
    case invalidValidationUnexpectedlyPassed

    var errorDescription: String? {
        switch self {
        case .notRunningAfterStart: "假核心启动后未进入运行状态"
        case .stateChangedAfterSuccessfulValidation: "成功检查配置后运行状态被改变"
        case .stateChangedAfterFailedValidation: "失败检查配置后运行状态被改变"
        case .invalidValidationUnexpectedlyPassed: "无效配置意外通过"
        }
    }
}
