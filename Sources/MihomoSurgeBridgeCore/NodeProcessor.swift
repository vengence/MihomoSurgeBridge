import CryptoKit
import Foundation

public enum NodeProcessor {
    public static func process(
        subscriptions: [(SubscriptionConfiguration, [RawSSRNode])]
    ) throws -> [ProcessedSubscription] {
        var usedNames: [String: Int] = [:]
        var output: [ProcessedSubscription] = []

        for (subscription, rawNodes) in subscriptions {
            let filtered = rawNodes.filter { node in
                let included = subscription.includeKeywords.isEmpty || containsAny(
                    subscription.includeKeywords,
                    in: node.originalName
                )
                let excluded = containsAny(subscription.excludeKeywords, in: node.originalName)
                return included && !excluded
            }

            let routed = try filtered.map { node in
                let baseName = subscription.namePrefix + node.originalName + subscription.nameSuffix
                let occurrence = (usedNames[baseName] ?? 0) + 1
                usedNames[baseName] = occurrence
                let displayName = occurrence == 1 ? baseName : "\(baseName) #\(occurrence)"
                let identity = try identity(for: node)
                let passwordDigest = SHA256.hash(data: Data("password:\(identity)".utf8)).hex
                return RoutedSSRNode(
                    identity: identity,
                    subscriptionID: node.subscriptionID,
                    originalName: node.originalName,
                    displayName: displayName,
                    internalName: "msb-\(identity.prefix(24))",
                    username: "msb_\(identity.prefix(20))",
                    password: String(passwordDigest.prefix(32)),
                    fields: node.fields
                )
            }
            output.append(.init(subscription: subscription, rawCount: rawNodes.count, nodes: routed))
        }
        return output
    }

    public static func matches(_ node: RoutedSSRNode, region: RegionConfiguration) -> Bool {
        containsAny(region.keywords, in: node.originalName)
    }

    private static func containsAny(_ keywords: [String], in value: String) -> Bool {
        keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .contains { value.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private static func identity(for node: RawSSRNode) throws -> String {
        struct Payload: Encodable {
            var subscriptionID: UUID
            var fields: [String: YAMLValue]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Payload(subscriptionID: node.subscriptionID, fields: node.fields))
        return SHA256.hash(data: data).hex
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
