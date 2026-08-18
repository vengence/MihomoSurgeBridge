import Foundation
import Yams

public enum ConfigurationGenerator {
    public static func mihomoYAML(nodes: [RoutedSSRNode], port: UInt16) throws -> String {
        let proxies: [[String: Any]] = nodes.map { node in
            var fields = node.fields.mapValues(\.anyValue)
            fields["name"] = node.internalName
            fields["type"] = "ssr"
            return fields
        }
        let users = nodes.map { ["username": $0.username, "password": $0.password] }
        let rules = nodes.map { "IN-USER,\($0.username),\($0.internalName)" } + ["MATCH,REJECT"]
        let root: [String: Any] = [
            "mode": "rule",
            "log-level": "warning",
            "ipv6": true,
            "allow-lan": false,
            "listeners": [[
                "name": "surge-socks",
                "type": "socks",
                "listen": "127.0.0.1",
                "port": Int(port),
                "udp": true,
                "users": users
            ]],
            "proxies": proxies,
            "rules": rules
        ]
        return try Yams.dump(object: root, sortKeys: true)
    }

    public static func surgeOutputs(
        processed: [ProcessedSubscription],
        regions: [RegionConfiguration],
        port: UInt16,
        outputDirectory: URL
    ) -> SurgeOutputBundle {
        var files: [String: String] = [:]
        var groups: [String] = []
        var usedGroupNames: [String: Int] = [:]
        let enabled = processed.filter(\.subscription.isEnabled)
        let allNodes = enabled.flatMap(\.nodes)

        for item in enabled {
            let filename = "subscription-\(item.subscription.id.uuidString.lowercased()).conf"
            files[filename] = policyFile(nodes: item.nodes, port: port)
            groups.append(groupLine(
                name: uniqueName(safePolicyName(item.subscription.name), used: &usedGroupNames),
                path: outputDirectory.appendingPathComponent(filename).path
            ))
        }

        files["all-ssr.conf"] = policyFile(nodes: allNodes, port: port)
        groups.append(groupLine(
            name: uniqueName("全部节点", used: &usedGroupNames),
            path: outputDirectory.appendingPathComponent("all-ssr.conf").path
        ))

        for region in regions {
            let filename = "region-\(region.id).conf"
            let nodes = allNodes.filter { NodeProcessor.matches($0, region: region) }
            files[filename] = policyFile(nodes: nodes, port: port)
            groups.append(groupLine(
                name: uniqueName(safePolicyName(region.name), used: &usedGroupNames),
                path: outputDirectory.appendingPathComponent(filename).path
            ))
        }
        return .init(files: files, groupLines: groups)
    }

    public static func policyFile(nodes: [RoutedSSRNode], port: UInt16) -> String {
        guard !nodes.isEmpty else { return "# 当前没有匹配的 SSR 节点\n" }
        return nodes.map { node in
            "\(safePolicyName(node.displayName)) = socks5, 127.0.0.1, \(port), username=\(node.username), password=\(node.password), udp-relay=true"
        }.joined(separator: "\n") + "\n"
    }

    private static func groupLine(name: String, path: String) -> String {
        let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\(name) = select, policy-path=\"\(escapedPath)\""
    }

    private static func uniqueName(_ name: String, used: inout [String: Int]) -> String {
        let occurrence = (used[name] ?? 0) + 1
        used[name] = occurrence
        return occurrence == 1 ? name : "\(name) #\(occurrence)"
    }

    public static func safePolicyName(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "=", with: "＝")
            .replacingOccurrences(of: ",", with: "，")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名节点" : cleaned
    }
}
