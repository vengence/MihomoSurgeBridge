import Foundation
import Yams

public enum SubscriptionParserError: LocalizedError, Equatable {
    case invalidUTF8
    case invalidRoot
    case missingProxies
    case noSSRNodes

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: "订阅不是有效的 UTF-8 文本"
        case .invalidRoot: "订阅 YAML 顶层必须是对象"
        case .missingProxies: "订阅缺少 proxies 节点列表"
        case .noSSRNodes: "订阅中没有有效的 SSR 节点"
        }
    }
}

public enum SubscriptionParser {
    public static func parse(data: Data, subscriptionID: UUID) throws -> [RawSSRNode] {
        guard let source = String(data: data, encoding: .utf8) else {
            throw SubscriptionParserError.invalidUTF8
        }
        let loaded = try Yams.load(yaml: source)
        guard let root = loaded as? [String: Any] else {
            throw SubscriptionParserError.invalidRoot
        }
        guard let proxies = root["proxies"] as? [Any] else {
            throw SubscriptionParserError.missingProxies
        }

        var result: [RawSSRNode] = []
        for item in proxies {
            guard let object = item as? [String: Any],
                  let type = object["type"] as? String,
                  type.caseInsensitiveCompare("ssr") == .orderedSame,
                  let name = object["name"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  object["server"] != nil,
                  object["port"] != nil else {
                continue
            }
            let converted = try object.mapValues(YAMLValue.convert)
            result.append(.init(subscriptionID: subscriptionID, originalName: name, fields: converted))
        }

        guard !result.isEmpty else { throw SubscriptionParserError.noSSRNodes }
        return result
    }
}
