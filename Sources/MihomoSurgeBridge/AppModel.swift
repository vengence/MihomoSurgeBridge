import AppKit
import Combine
import Foundation
import MihomoSurgeBridgeCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published private(set) var currentNodes: [RoutedSSRNode] = []
    @Published private(set) var surgeGroupBlock = ""
    @Published private(set) var outputFiles: [URL] = []
    @Published private(set) var lastGeneratedAt: Date?
    @Published var statusMessage = "正在准备…"
    @Published private(set) var isBusy = false
    @Published private(set) var hasStarted = false
    @Published private(set) var outboundSnapshot = OutboundNetworkSnapshot(
        services: [], preferredServiceName: nil, interfaceName: nil,
        fallbackReason: nil, defaultNetworkName: "系统默认网络"
    )
    @Published private(set) var appliedOutboundInterface: String?
    @Published private(set) var outboundSwitchError: String?

    let paths: AppPaths
    let mihomo = MihomoManager.shared

    private let configurationStore: ConfigurationStore
    private let cacheStore: CacheStore
    private let client = SubscriptionClient()
    private let installer = ManagedMihomoInstaller()
    private let logger: AppLogger
    private let outboundObserver = OutboundNetworkObserver()
    private var schedulerTask: Task<Void, Never>?
    private var lastRuntimeSignature: String?
    private var runtimeOutboundInterface: String?
    private var networkRefreshInProgress = false

    init(root: URL? = nil) {
        let paths = AppPaths(root: root)
        self.paths = paths
        configurationStore = ConfigurationStore(url: paths.config)
        cacheStore = CacheStore(paths: paths)
        logger = AppLogger(url: paths.appLog)
        do {
            try paths.ensureDirectories()
            configuration = try configurationStore.load()
        } catch {
            configuration = .init()
            statusMessage = "配置读取失败，已使用默认值：\(error.localizedDescription)"
        }
        if configuration.socksPort == nil {
            configuration.socksPort = PortChecker.firstAvailable()
            try? configurationStore.save(configuration)
        }
    }

    deinit { schedulerTask?.cancel() }

    var outputDirectory: URL {
        configuration.outputDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? paths.generated
    }

    var resolvedMihomo: URL? {
        MihomoLocator.locate(source: configuration.mihomoSource, paths: paths)
    }

    var outboundStatusText: String {
        if !mihomo.state.isRunning {
            if let outboundSwitchError {
                let configured = runtimeOutboundInterface.map { "USB（\($0)）" } ?? "系统默认网络"
                return "出口切换失败，运行配置仍为\(configured)：\(outboundSwitchError)"
            }
            return "下次启动将使用：\(outboundSnapshot.targetDescription)"
        }
        if let outboundSwitchError {
            return "出口切换失败，当前仍使用\(appliedOutboundInterface.map { " USB（\($0)）" } ?? "系统默认网络")：\(outboundSwitchError)"
        }
        if let appliedOutboundInterface {
            return "当前出口：USB（\(appliedOutboundInterface)）"
        }
        return "当前出口：系统默认网络（\(outboundSnapshot.defaultNetworkName)）"
    }

    func startupOnce() async {
        guard !hasStarted else { return }
        hasStarted = true
        logger.log("应用启动")
        do {
            outboundSnapshot = await inspectOutboundNetwork()
            runtimeOutboundInterface = outboundSnapshot.interfaceName
            try regenerate()
            if configuration.desiredMihomoRunning, !currentNodes.isEmpty, let executable = resolvedMihomo {
                await mihomo.cleanupOrphan(executable: executable, config: paths.runtimeConfig)
                try await mihomo.start(
                    executable: executable,
                    config: paths.runtimeConfig,
                    runtime: paths.runtime,
                    logURL: paths.mihomoLog
                )
                appliedOutboundInterface = runtimeOutboundInterface
            }
        } catch {
            report(error)
        }
        startScheduler()
        outboundObserver.start { [weak self] in
            Task { await self?.refreshOutboundNetwork() }
        }
        await refreshAutomatically()
    }

    func saveConfiguration(regenerate shouldRegenerate: Bool = true) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try configurationStore.save(configuration)
            if shouldRegenerate {
                let before = lastRuntimeSignature
                let previousInterface = runtimeOutboundInterface
                let previousYAML = try? Data(contentsOf: paths.runtimeConfig)
                outboundSnapshot = await inspectOutboundNetwork()
                runtimeOutboundInterface = outboundSnapshot.interfaceName
                try regenerate()
                if mihomo.state.isRunning, before != lastRuntimeSignature {
                    do {
                        try await restartMihomoPreservingPreference()
                        outboundSwitchError = nil
                    } catch {
                        restoreRuntime(previousYAML, interface: previousInterface, signature: before)
                        try? await restartMihomoPreservingPreference()
                        outboundSwitchError = error.localizedDescription
                        throw error
                    }
                } else {
                    outboundSwitchError = nil
                }
            }
            statusMessage = "设置已保存"
        } catch { report(error) }
    }

    func setPreferredUSBServiceID(_ serviceID: String?) async {
        configuration.preferredUSBServiceID = serviceID
        await saveConfiguration()
    }

    func addOrUpdate(_ subscription: SubscriptionConfiguration) async {
        if let index = configuration.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            configuration.subscriptions[index] = subscription
        } else {
            configuration.subscriptions.append(subscription)
        }
        await saveConfiguration()
    }

    func deleteSubscription(_ id: UUID) async {
        configuration.subscriptions.removeAll { $0.id == id }
        try? cacheStore.remove(subscriptionID: id)
        await saveConfiguration()
    }

    func refreshAutomatically() async {
        let ids = configuration.subscriptions.filter(\.autoUpdate).map(\.id)
        await refresh(ids: ids, reason: "启动后台刷新")
    }

    func refreshAll() async {
        await refresh(ids: configuration.subscriptions.map(\.id), reason: "手动更新全部")
    }

    func refresh(subscriptionID: UUID) async {
        await refresh(ids: [subscriptionID], reason: "手动更新订阅")
    }

    private func refresh(ids: [UUID], reason: String) async {
        guard !ids.isEmpty else {
            statusMessage = "没有需要更新的订阅"
            return
        }
        isBusy = true
        statusMessage = reason
        let before = lastRuntimeSignature
        let configurationBeforeRefresh = configuration
        var oldCaches: [UUID: Data?] = [:]
        for id in ids {
            guard let index = configuration.subscriptions.firstIndex(where: { $0.id == id }) else { continue }
            let subscription = configuration.subscriptions[index]
            do {
                let data = try await client.download(subscription.url)
                let raw = try SubscriptionParser.parse(data: data, subscriptionID: id)
                oldCaches[id] = try cacheStore.load(subscriptionID: id)
                try cacheStore.save(data, subscriptionID: id)
                configuration.subscriptions[index].lastSuccessfulUpdate = Date()
                configuration.subscriptions[index].lastError = nil
                configuration.subscriptions[index].rawNodeCount = raw.count
                logger.log("订阅更新成功：\(subscription.name)，\(raw.count) 个 SSR 节点")
            } catch {
                configuration.subscriptions[index].lastError = error.localizedDescription
                logger.log("订阅更新失败：\(subscription.name)：\(error.localizedDescription)")
            }
        }
        configuration.lastScheduledRefreshAt = Date()
        do {
            try configurationStore.save(configuration)
            try regenerate()
            if mihomo.state.isRunning, before != lastRuntimeSignature {
                try await restartMihomoPreservingPreference()
            }
            let failures = configuration.subscriptions.filter { ids.contains($0.id) && $0.lastError != nil }.count
            statusMessage = failures == 0 ? "订阅更新完成" : "更新完成，\(failures) 个订阅失败并保留旧缓存"
        } catch {
            for (id, oldData) in oldCaches {
                if let oldData { try? cacheStore.save(oldData, subscriptionID: id) }
                else { try? cacheStore.remove(subscriptionID: id) }
            }
            configuration = configurationBeforeRefresh
            try? regenerate()
            report(error)
        }
        isBusy = false
    }

    func regenerate() throws {
        let previousErrors = Dictionary(uniqueKeysWithValues: configuration.subscriptions.map { ($0.id, $0.lastError) })
        var rawByID: [UUID: [RawSSRNode]] = [:]
        for index in configuration.subscriptions.indices {
            let id = configuration.subscriptions[index].id
            guard let data = try cacheStore.load(subscriptionID: id) else {
                configuration.subscriptions[index].rawNodeCount = 0
                configuration.subscriptions[index].filteredNodeCount = 0
                continue
            }
            do {
                let raw = try SubscriptionParser.parse(data: data, subscriptionID: id)
                rawByID[id] = raw
                configuration.subscriptions[index].rawNodeCount = raw.count
            } catch {
                configuration.subscriptions[index].lastError = "缓存无效：\(error.localizedDescription)"
            }
        }

        let inputs = configuration.subscriptions
            .filter(\.isEnabled)
            .map { ($0, rawByID[$0.id] ?? []) }
        let processed = try NodeProcessor.process(subscriptions: inputs)
        let counts = Dictionary(uniqueKeysWithValues: processed.map { ($0.subscription.id, $0.nodes.count) })
        for index in configuration.subscriptions.indices {
            configuration.subscriptions[index].filteredNodeCount = counts[configuration.subscriptions[index].id] ?? 0
            if configuration.subscriptions[index].lastError?.hasPrefix("缓存无效：") != true {
                configuration.subscriptions[index].lastError = previousErrors[configuration.subscriptions[index].id] ?? nil
            }
        }

        let nodes = processed.flatMap(\.nodes)
        let port = configuration.socksPort ?? PortChecker.firstAvailable() ?? 17_892
        configuration.socksPort = port
        let output = ConfigurationGenerator.surgeOutputs(
            processed: processed,
            regions: configuration.regions,
            port: port,
            outputDirectory: outputDirectory
        )
        let mihomoYAML = try ConfigurationGenerator.mihomoYAML(
            nodes: nodes, port: port, outboundInterface: runtimeOutboundInterface
        )
        var files: [URL: Data] = [paths.runtimeConfig: Data(mihomoYAML.utf8)]
        for (name, content) in output.files {
            files[outputDirectory.appendingPathComponent(name)] = Data(content.utf8)
        }
        try AtomicFiles.write(files)
        try removeStaleGeneratedFiles(keeping: Set(output.files.keys))
        try configurationStore.save(configuration)
        currentNodes = nodes
        lastRuntimeSignature = runtimeSignature(nodes: nodes)
        surgeGroupBlock = output.completeProxyGroupBlock
        outputFiles = output.files.keys.sorted().map { outputDirectory.appendingPathComponent($0) }
        lastGeneratedAt = Date()
        if statusMessage == "正在准备…" { statusMessage = "已使用本地缓存准备就绪" }
    }

    func startMihomo() async {
        guard !currentNodes.isEmpty else {
            statusMessage = "没有可用节点，请先添加并更新订阅"
            return
        }
        guard let executable = resolvedMihomo else {
            statusMessage = "未找到 Mihomo，请安装 Homebrew Mihomo 或使用应用托管安装"
            return
        }
        guard let port = configuration.socksPort, PortChecker.isAvailable(port) else {
            statusMessage = "端口被占用，请在设置中更换端口"
            return
        }
        await refreshOutboundNetwork(force: true)
        guard runtimeOutboundInterface == outboundSnapshot.interfaceName else {
            statusMessage = "出口配置尚未切换成功，请检查设置中的回退原因"
            return
        }
        isBusy = true
        do {
            await mihomo.cleanupOrphan(executable: executable, config: paths.runtimeConfig)
            try await mihomo.start(
                executable: executable,
                config: paths.runtimeConfig,
                runtime: paths.runtime,
                logURL: paths.mihomoLog
            )
            configuration.desiredMihomoRunning = true
            appliedOutboundInterface = runtimeOutboundInterface
            outboundSwitchError = nil
            try configurationStore.save(configuration)
            statusMessage = "Mihomo 已启动"
        } catch { report(error) }
        isBusy = false
    }

    func stopMihomo() async {
        isBusy = true
        await mihomo.stop()
        appliedOutboundInterface = nil
        configuration.desiredMihomoRunning = false
        try? configurationStore.save(configuration)
        statusMessage = "Mihomo 已停止，定时更新继续运行"
        isBusy = false
    }

    func validateMihomo() async {
        guard let executable = resolvedMihomo else {
            statusMessage = "未找到 Mihomo"
            return
        }
        isBusy = true
        statusMessage = "正在检查应用生成的 Mihomo 配置…"
        do {
            _ = try await mihomo.validate(executable: executable, config: paths.runtimeConfig)
            statusMessage = "Mihomo 生成配置检查通过；运行状态未改变"
        } catch { report(error) }
        isBusy = false
    }

    func validateSurgeOutputs() async {
        let cli = URL(fileURLWithPath: "/Applications/Surge.app/Contents/Applications/surge-cli")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            statusMessage = "未检测到 Surge CLI，已跳过输出校验"
            return
        }
        let validation = paths.runtime.appendingPathComponent("surge-output-validation.conf")
        let allPath = outputDirectory.appendingPathComponent("all-ssr.conf").path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let profile = """
        [General]
        loglevel = notify

        [Proxy]

        [Proxy Group]
        MihomoSurgeBridge 验证 = select, policy-path="\(allPath)"

        [Rule]
        FINAL,DIRECT
        """
        do {
            try Data(profile.utf8).write(to: validation, options: .atomic)
            let result = try await Task.detached {
                try ProcessRunner.run(cli, arguments: ["--check", validation.path])
            }.value
            try? FileManager.default.removeItem(at: validation)
            guard result.status == 0 else { throw AppModelError.surgeValidation(result.output) }
            statusMessage = "Surge 输出格式校验通过"
        } catch {
            try? FileManager.default.removeItem(at: validation)
            report(error)
        }
    }

    func installManagedMihomo() async {
        isBusy = true
        statusMessage = "正在下载并校验 Mihomo…"
        do {
            let version = try await installer.install(to: paths.managedMihomo)
            configuration.mihomoSource = .managed
            try configurationStore.save(configuration)
            statusMessage = "Mihomo 安装完成：\(version)"
        } catch { report(error) }
        isBusy = false
    }

    func testProxyConnectivity() async {
        guard mihomo.state.isRunning, let port = configuration.socksPort, let node = currentNodes.first else {
            statusMessage = "请先启动 Mihomo，并确保至少有一个节点"
            return
        }
        isBusy = true
        statusMessage = "正在测试代理连通性（使用：\(node.displayName)）…"
        let proxy = "socks5h://\(node.username):\(node.password)@127.0.0.1:\(port)"
        let result = await Task.detached {
            try? ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: ["--silent", "--show-error", "--max-time", "12", "--proxy", proxy, "https://cp.cloudflare.com/generate_204"]
            )
        }.value
        if let result, result.status == 0 {
            statusMessage = "首个节点连通性测试通过：\(node.displayName)"
        } else {
            let detail = result.map { "curl 退出码 \($0.status)" } ?? "测试命令未能启动"
            statusMessage = "首个节点测试失败：\(node.displayName)（\(detail)）。其他节点未测试，请查看 Mihomo 日志"
        }
        isBusy = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            configuration.launchAtLogin = enabled
            try configurationStore.save(configuration)
            statusMessage = enabled ? "已启用登录时启动" : "已关闭登录时启动"
        } catch { report(error) }
    }

    func exportConfiguration(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(MigrationDocument(configuration: configuration)).write(to: url, options: .atomic)
    }

    func importConfiguration(from url: URL) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(MigrationDocument.self, from: Data(contentsOf: url))
        guard document.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
        let previousConfiguration = configuration
        let previousInterface = runtimeOutboundInterface
        let previousSignature = lastRuntimeSignature
        let previousSnapshot = outboundSnapshot
        configuration = document.applying(to: configuration)
        if configuration.socksPort == nil { configuration.socksPort = PortChecker.firstAvailable() }
        outboundSnapshot = await inspectOutboundNetwork()
        runtimeOutboundInterface = outboundSnapshot.interfaceName
        do {
            try configurationStore.save(configuration)
            try regenerate()
            if mihomo.state.isRunning, previousSignature != lastRuntimeSignature {
                try await restartMihomoPreservingPreference()
            }
            outboundSwitchError = nil
            statusMessage = "配置导入完成，请更新订阅"
        } catch {
            configuration = previousConfiguration
            runtimeOutboundInterface = previousInterface
            outboundSnapshot = previousSnapshot
            try? regenerate()
            if !mihomo.state.isRunning, previousConfiguration.desiredMihomoRunning {
                try? await restartMihomoPreservingPreference()
            }
            throw error
        }
    }

    func quitApplication() async {
        schedulerTask?.cancel()
        outboundObserver.stop()
        await mihomo.stop()
        logger.log("应用正常退出，已停止 Mihomo")
        NSApplication.shared.terminate(nil)
    }

    private func restartMihomoPreservingPreference() async throws {
        guard let executable = resolvedMihomo else { throw AppModelError.mihomoMissing }
        try await mihomo.restart(
            executable: executable,
            config: paths.runtimeConfig,
            runtime: paths.runtime,
            logURL: paths.mihomoLog
        )
        appliedOutboundInterface = runtimeOutboundInterface
    }

    private func runtimeSignature(nodes: [RoutedSSRNode]) -> String {
        let port = configuration.socksPort.map(String.init) ?? "none"
        let executable = resolvedMihomo?.path ?? "missing"
        return ([port, executable, runtimeOutboundInterface ?? "system"] + nodes.map(\.identity))
            .joined(separator: ":")
    }

    private func inspectOutboundNetwork() async -> OutboundNetworkSnapshot {
        let serviceID = configuration.preferredUSBServiceID
        return await Task.detached(priority: .utility) {
            OutboundNetworkDetector.inspect(preferredServiceID: serviceID)
        }.value
    }

    func refreshOutboundNetwork(force: Bool = false) async {
        while force && networkRefreshInProgress {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !networkRefreshInProgress, !isBusy else { return }
        networkRefreshInProgress = true
        defer { networkRefreshInProgress = false }
        let serviceID = configuration.preferredUSBServiceID
        let snapshot = await inspectOutboundNetwork()
        guard serviceID == configuration.preferredUSBServiceID else { return }
        outboundSnapshot = snapshot
        guard snapshot.interfaceName != runtimeOutboundInterface else {
            outboundSwitchError = nil
            return
        }
        let previousInterface = runtimeOutboundInterface
        let previousSignature = lastRuntimeSignature
        let previousYAML = try? Data(contentsOf: paths.runtimeConfig)
        let candidate = paths.runtime.appendingPathComponent("mihomo-candidate.yaml")
        defer { try? FileManager.default.removeItem(at: candidate) }
        do {
            let yaml = try ConfigurationGenerator.mihomoYAML(
                nodes: currentNodes,
                port: configuration.socksPort ?? 17_892,
                outboundInterface: snapshot.interfaceName
            )
            try Data(yaml.utf8).write(to: candidate, options: .atomic)
            if let executable = resolvedMihomo {
                _ = try await mihomo.validate(executable: executable, config: candidate)
            }
            guard serviceID == configuration.preferredUSBServiceID else { return }
            try Data(yaml.utf8).write(to: paths.runtimeConfig, options: .atomic)
            runtimeOutboundInterface = snapshot.interfaceName
            lastRuntimeSignature = runtimeSignature(nodes: currentNodes)
            if mihomo.state.isRunning { try await restartMihomoPreservingPreference() }
            outboundSwitchError = nil
            logger.log("代理出口切换为：\(snapshot.targetDescription)")
        } catch {
            restoreRuntime(previousYAML, interface: previousInterface, signature: previousSignature)
            if !mihomo.state.isRunning, configuration.desiredMihomoRunning {
                try? await restartMihomoPreservingPreference()
            }
            outboundSwitchError = error.localizedDescription
            logger.log("代理出口切换失败：\(error.localizedDescription)")
        }
    }

    private func restoreRuntime(_ yaml: Data?, interface: String?, signature: String?) {
        if let yaml { try? yaml.write(to: paths.runtimeConfig, options: .atomic) }
        runtimeOutboundInterface = interface
        lastRuntimeSignature = signature
    }

    private func startScheduler() {
        schedulerTask?.cancel()
        let interval = max(configuration.updateIntervalSeconds, 60)
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await self.refreshAutomatically()
            }
        }
    }

    private func removeStaleGeneratedFiles(keeping names: Set<String>) throws {
        guard FileManager.default.fileExists(atPath: outputDirectory.path) else { return }
        let knownFixed = Set(["all-ssr.conf", "region-hk.conf", "region-jp.conf", "region-sg.conf", "region-tw.conf", "region-us.conf"])
        for url in try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            let owned = knownFixed.contains(name) || (name.hasPrefix("subscription-") && name.hasSuffix(".conf"))
            if owned && !names.contains(name) { try FileManager.default.removeItem(at: url) }
        }
    }

    private func report(_ error: Error) {
        statusMessage = error.localizedDescription
        logger.log("错误：\(error.localizedDescription)")
    }
}

enum AppModelError: LocalizedError {
    case mihomoMissing
    case surgeValidation(String)

    var errorDescription: String? {
        switch self {
        case .mihomoMissing: "未找到 Mihomo"
        case let .surgeValidation(message): "Surge 输出校验失败：\(message)"
        }
    }
}
