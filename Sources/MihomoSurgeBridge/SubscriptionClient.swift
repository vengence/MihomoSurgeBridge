import Foundation

actor SubscriptionClient {
    private let session: URLSession
    private let maximumSize = 10 * 1_024 * 1_024

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("MihomoSurgeBridge/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ... 299).contains(response.statusCode) else {
            throw DownloadError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard data.count <= maximumSize else { throw DownloadError.tooLarge }
        return data
    }
}

enum DownloadError: LocalizedError {
    case http(Int)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case let .http(code): "订阅下载失败（HTTP \(code)）"
        case .tooLarge: "订阅文件超过 10 MB 限制"
        }
    }
}
