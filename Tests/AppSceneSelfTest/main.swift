import Foundation

@main
struct AppSceneSelfTest {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("用法：AppSceneSelfTest <MihomoSurgeBridgeApp.swift>\n", stderr)
            exit(EXIT_FAILURE)
        }

        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        guard source.contains("Window(\"MihomoSurgeBridge\", id: \"main\")"),
              !source.contains("WindowGroup(\"MihomoSurgeBridge\", id: \"main\")") else {
            fputs("✗ 主界面没有使用单例 Window 场景\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("✓ 主界面使用单例 Window 场景")
    }
}
