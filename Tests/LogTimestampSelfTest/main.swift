import Foundation

@main
struct LogTimestampSelfTest {
    static func main() {
        guard let singapore = TimeZone(secondsFromGMT: 8 * 60 * 60) else {
            fputs("✗ 无法创建测试时区\n", stderr)
            exit(EXIT_FAILURE)
        }

        let epoch = Date(timeIntervalSince1970: 0)
        let value = LogTimestampFormatter.string(from: epoch, timeZone: singapore)
        guard value == "1970-01-01T08:00:00+08:00" else {
            fputs("✗ 日志时区格式错误：\(value)\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("✓ 日志使用本地 ISO 8601 时区：\(value)")
    }
}
