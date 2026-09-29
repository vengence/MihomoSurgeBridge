import Darwin
import Foundation
import MihomoSurgeBridgeCore

private var failures: [String] = []

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("✓ \(message)") }
    else {
        print("✗ \(message)")
        failures.append(message)
    }
}

do {
    let subscriptionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let fixture = Data(
        """
        proxies:
          - name: "🇭🇰 香港 A"
            type: ssr
            server: hk.example.invalid
            port: 443
            cipher: aes-256-cfb
            password: fake-password-a
            protocol: auth_sha1_v4
            protocol-param: fake-param-a
            obfs: tls1.2_ticket_auth
            obfs-param: example.invalid
          - name: "Japan B"
            type: ssr
            server: jp.example.invalid
            port: 8443
            cipher: aes-256-cfb
            password: fake-password-b
            protocol: auth_sha1_v4
            protocol-param: fake-param-b
            obfs: tls1.2_ticket_auth
            obfs-param: example.invalid
          - name: "Blocked US"
            type: ssr
            server: us.example.invalid
            port: 9443
            cipher: aes-256-cfb
            password: fake-password-c
            protocol: auth_sha1_v4
            protocol-param: fake-param-c
            obfs: tls1.2_ticket_auth
            obfs-param: example.invalid
          - name: "Ignored SS"
            type: ss
            server: ss.example.invalid
            port: 443
            cipher: aes-128-gcm
            password: fake
        """.utf8
    )
    let raw = try SubscriptionParser.parse(data: fixture, subscriptionID: subscriptionID)
    check(raw.count == 3, "仅提取 SSR 节点")

    let subscription = SubscriptionConfiguration(
        id: subscriptionID,
        name: "测试",
        url: URL(string: "https://example.invalid/subscription.yaml")!,
        includeKeywords: ["香港", "Japan"],
        excludeKeywords: ["blocked"],
        namePrefix: "测试 · "
    )
    let first = try NodeProcessor.process(subscriptions: [(subscription, raw)])
    let second = try NodeProcessor.process(subscriptions: [(subscription, raw)])
    check(first[0].nodes.count == 2, "保留与排除关键词")
    check(first[0].nodes[0].displayName == "测试 · 🇭🇰 香港 A", "前缀命名")
    check(first[0].nodes.map(\.identity) == second[0].nodes.map(\.identity), "节点身份稳定")
    check(NodeProcessor.matches(first[0].nodes[0], region: RegionConfiguration.defaults[0]), "地区关键词匹配")

    let port: UInt16 = 32_123
    let yaml = try ConfigurationGenerator.mihomoYAML(nodes: first[0].nodes, port: port)
    check(yaml.contains("IN-USER"), "生成 IN-USER 路由")
    check(yaml.contains("127.0.0.1"), "仅监听本地回环")
    check(!yaml.contains("interface-name"), "系统自动模式不绑定出口网卡")
    let usbYAML = try ConfigurationGenerator.mihomoYAML(
        nodes: first[0].nodes, port: port, outboundInterface: "en5"
    )
    check(usbYAML.components(separatedBy: "interface-name: en5").count - 1 == first[0].nodes.count,
          "USB 模式为每个代理节点绑定出口网卡")
    check(!usbYAML.split(separator: "\n").contains { $0.hasPrefix("interface-name:") },
          "USB 模式不全局绑定 DNS 出口")
    check(usbYAML.contains("127.0.0.1"), "绑定出口不改变本地 SOCKS5 监听")
    let outputs = ConfigurationGenerator.surgeOutputs(
        processed: first,
        regions: RegionConfiguration.defaults,
        port: port,
        outputDirectory: URL(fileURLWithPath: "/tmp/Mihomo Surge Bridge")
    )
    check(outputs.files.keys.filter { $0.hasPrefix("region-") }.count == 5, "生成五个地区文件")
    check(outputs.files["all-ssr.conf"]?.contains("socks5, 127.0.0.1, 32123") == true, "生成 Surge SOCKS5 策略")
    check(outputs.completeProxyGroupBlock.contains("policy-path="), "生成 Surge 策略组区块")
    check(outputs.groupLines.contains { $0.hasPrefix("全部节点 =") }, "汇总策略组不带 SSR 后缀")
    check(outputs.groupLines.contains { $0.hasPrefix("香港 =") }, "地区策略组不带 SSR 后缀")
    check(!outputs.groupLines.contains { $0.hasPrefix("全部 SSR =") || $0.hasPrefix("香港 SSR =") }, "输出策略组移除 SSR 文案")

    var configuration = AppConfiguration()
    configuration.socksPort = 19_999
    configuration.outputDirectory = "/private/tmp/output"
    configuration.mihomoSource = .homebrew
    configuration.preferredUSBServiceID = "test-service-id"
    configuration.subscriptions = [subscription]
    let imported = MigrationDocument(configuration: configuration).applying()
    check(imported.socksPort == nil && imported.outputDirectory == nil, "迁移不携带机器路径和端口")
    check(imported.preferredUSBServiceID == nil, "迁移不携带设备专属网络服务")
    let encoder = JSONEncoder()
    let encoded = try encoder.encode(configuration)
    var legacyJSON = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    legacyJSON.removeValue(forKey: "preferredUSBServiceID")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
    let loadedLegacy = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)
    check(loadedLegacy.preferredUSBServiceID == nil, "旧版配置默认系统自动")

    let mihomoPath = ["/opt/homebrew/bin/mihomo", "/usr/local/bin/mihomo"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    if let mihomoPath {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("MihomoSurgeBridgeSelfTest-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data(yaml.utf8).write(to: temporary)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mihomoPath)
        process.arguments = ["-t", "-f", temporary.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        check(process.terminationStatus == 0, "Mihomo 接受生成的配置")
    } else {
        print("– 未安装 Homebrew Mihomo，跳过真实配置校验")
    }
} catch {
    failures.append(error.localizedDescription)
    print("✗ 自检异常：\(error.localizedDescription)")
}

if failures.isEmpty {
    print("\n全部自检通过")
} else {
    print("\n自检失败：\(failures.count) 项")
    exit(EXIT_FAILURE)
}
