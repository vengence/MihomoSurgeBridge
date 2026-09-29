import AppKit
import MihomoSurgeBridgeCore
import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case subscriptions = "订阅"
    case regions = "地区"
    case outputs = "输出"
    case settings = "设置与诊断"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .subscriptions: "link"
        case .regions: "globe.asia.australia"
        case .outputs: "doc.on.doc"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationTitle("MihomoSurgeBridge")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .subscriptions: SubscriptionsView()
            case .regions: RegionsView()
            case .outputs: OutputsView()
            case .settings: SettingsDiagnosticsView()
            }
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mihomo: MihomoManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("概览").font(.largeTitle.bold())
                HStack(spacing: 14) {
                    StatusCard(title: "Mihomo", value: mihomo.state.label, icon: "bolt.horizontal.circle")
                    StatusCard(title: "SOCKS5", value: "127.0.0.1:\(model.configuration.socksPort.map(String.init) ?? "未设置")", icon: "network")
                    StatusCard(title: "可用 SSR 节点", value: "\(model.currentNodes.count)", icon: "point.3.connected.trianglepath.dotted")
                }

                HStack {
                    if mihomo.state.isRunning {
                        Button("停止 Mihomo", role: .destructive) { Task { await model.stopMihomo() } }
                    } else {
                        Button("启动 Mihomo") { Task { await model.startMihomo() } }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("立即更新全部") { Task { await model.refreshAll() } }
                    Button("检查生成配置") { Task { await model.validateMihomo() } }
                        .help("验证应用生成的 Mihomo YAML 能否被当前 Mihomo 解析；不会测试节点网络，也不会改变运行状态")
                    Button("测试首个节点连通性") { Task { await model.testProxyConnectivity() } }
                        .help("使用第一个可用节点，端到端测试本地 SOCKS5、认证路由和外网访问")
                }
                .disabled(model.isBusy)

                GroupBox("当前状态") {
                    HStack {
                        if model.isBusy { ProgressView().controlSize(.small) }
                        Text(model.statusMessage).textSelection(.enabled)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                }

                GroupBox("订阅") {
                    if model.configuration.subscriptions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "link.badge.plus").font(.system(size: 32)).foregroundStyle(.secondary)
                            Text("还没有订阅").font(.headline)
                            Text("请在“订阅”页面添加 Clash/Mihomo YAML 地址。")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.configuration.subscriptions) { item in
                                HStack {
                                    Circle().fill(item.lastError == nil ? Color.green : Color.orange).frame(width: 8, height: 8)
                                    Text(item.name)
                                    Spacer()
                                    Text("\(item.rawNodeCount) → \(item.filteredNodeCount)")
                                        .monospacedDigit().foregroundStyle(.secondary)
                                    if let date = item.lastSuccessfulUpdate {
                                        Text(date, style: .relative).foregroundStyle(.secondary)
                                    } else {
                                        Text("未更新").foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 7)
                                if item.id != model.configuration.subscriptions.last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                Spacer(minLength: 12)
            }
            .padding(24)
        }
    }
}

private struct StatusCard: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
    }
}

struct SubscriptionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: SubscriptionConfiguration?
    @State private var presentingNew = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("订阅").font(.largeTitle.bold())
                Spacer()
                Button { presentingNew = true } label: { Label("添加订阅", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)

            if model.configuration.subscriptions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "link").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("添加第一个 YAML 订阅").font(.title3.bold())
                    Text("MVP 仅提取 proxies: 中 type: ssr 的节点。").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(model.configuration.subscriptions) { subscription in
                        SubscriptionRow(subscription: subscription) {
                            editing = subscription
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $presentingNew) {
            SubscriptionEditor(subscription: nil)
        }
        .sheet(item: $editing) { subscription in
            SubscriptionEditor(subscription: subscription)
        }
    }
}

private struct SubscriptionRow: View {
    @EnvironmentObject private var model: AppModel
    var subscription: SubscriptionConfiguration
    var edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { subscription.isEnabled },
                set: { value in
                    var updated = subscription
                    updated.isEnabled = value
                    Task { await model.addOrUpdate(updated) }
                }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(subscription.name).font(.headline)
                    if subscription.autoUpdate {
                        Label("每小时", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("此订阅每小时自动更新")
                    }
                }
                Text(subscription.url.absoluteString).lineLimit(1).foregroundStyle(.secondary)
                if let error = subscription.lastError {
                    Text(error).lineLimit(2).foregroundStyle(.orange).font(.caption)
                }
            }
            Spacer()
            Text("\(subscription.rawNodeCount) → \(subscription.filteredNodeCount)")
                .monospacedDigit().foregroundStyle(.secondary)
            Button("更新") { Task { await model.refresh(subscriptionID: subscription.id) } }
            Button("编辑", action: edit)
            Button(role: .destructive) { Task { await model.deleteSubscription(subscription.id) } } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }
}

private struct SubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var id: UUID
    @State private var name: String
    @State private var urlText: String
    @State private var enabled: Bool
    @State private var autoUpdate: Bool
    @State private var includeText: String
    @State private var excludeText: String
    @State private var prefix: String
    @State private var suffix: String
    @State private var errorMessage: String?
    private let isNew: Bool
    private let original: SubscriptionConfiguration?

    init(subscription: SubscriptionConfiguration?) {
        isNew = subscription == nil
        original = subscription
        _id = State(initialValue: subscription?.id ?? UUID())
        _name = State(initialValue: subscription?.name ?? "")
        _urlText = State(initialValue: subscription?.url.absoluteString ?? "")
        _enabled = State(initialValue: subscription?.isEnabled ?? true)
        _autoUpdate = State(initialValue: subscription?.autoUpdate ?? true)
        _includeText = State(initialValue: subscription?.includeKeywords.joined(separator: ", ") ?? "")
        _excludeText = State(initialValue: subscription?.excludeKeywords.joined(separator: ", ") ?? "")
        _prefix = State(initialValue: subscription?.namePrefix ?? "")
        _suffix = State(initialValue: subscription?.nameSuffix ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(name.isEmpty ? "添加订阅" : "编辑订阅").font(.title2.bold())
            Form {
                TextField("名称", text: $name)
                TextField("YAML URL", text: $urlText)
                Toggle("启用订阅", isOn: $enabled)
                Toggle("每小时自动更新", isOn: $autoUpdate)
                TextField("保留关键词（逗号分隔）", text: $includeText)
                TextField("排除关键词（逗号分隔）", text: $excludeText)
                TextField("名称前缀", text: $prefix)
                TextField("名称后缀", text: $suffix)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func save() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            errorMessage = "请输入有效的 HTTP 或 HTTPS URL"
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMessage = "请输入订阅名称"
            return
        }
        let subscription = SubscriptionConfiguration(
            id: id,
            name: cleanName,
            url: url,
            isEnabled: enabled,
            autoUpdate: autoUpdate,
            includeKeywords: split(includeText),
            excludeKeywords: split(excludeText),
            namePrefix: isNew && prefix.isEmpty ? "\(cleanName) · " : prefix,
            nameSuffix: suffix,
            lastSuccessfulUpdate: original?.lastSuccessfulUpdate,
            lastError: original?.lastError,
            rawNodeCount: original?.rawNodeCount ?? 0,
            filteredNodeCount: original?.filteredNodeCount ?? 0
        )
        Task {
            await model.addOrUpdate(subscription)
            dismiss()
        }
    }

    private func split(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct RegionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("地区规则").font(.largeTitle.bold())
                Text("关键词命中任意一个即归入该地区，匹配原始节点名称且忽略英文大小写。")
                    .foregroundStyle(.secondary)
                ForEach($model.configuration.regions) { $region in
                    GroupBox(region.name) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("关键词", text: Binding(
                                get: { region.keywords.joined(separator: ", ") },
                                set: { region.keywords = splitKeywords($0) }
                            ))
                            let count = model.currentNodes.filter { NodeProcessor.matches($0, region: region) }.count
                            Text("当前匹配 \(count) 个节点 · \(region.keywords.joined(separator: " OR "))")
                                .font(.caption).foregroundStyle(count == 0 ? .orange : .secondary)
                        }
                        .padding(6)
                    }
                }
                Button("保存地区规则") { Task { await model.saveConfiguration() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }

    private func splitKeywords(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct OutputsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Surge 输出").font(.largeTitle.bold())
            HStack {
                Button("复制完整 [Proxy Group] 区块") { copy(model.surgeGroupBlock) }
                    .buttonStyle(.borderedProminent)
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.outputDirectory])
                }
                Button("重新生成") { Task { await model.saveConfiguration() } }
                Button("使用 Surge CLI 校验") { Task { await model.validateSurgeOutputs() } }
            }
            GroupBox("使用方式") {
                Text("应用不会修改 Surge。复制下面的策略组到你的 Surge 配置，再把所需组名加入现有“节点选择”。")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            TextEditor(text: .constant(model.surgeGroupBlock))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            List(model.outputFiles, id: \.path) { file in
                HStack {
                    Image(systemName: "doc.text")
                    VStack(alignment: .leading) {
                        Text(file.lastPathComponent)
                        Text(file.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("复制路径") { copy(file.path) }
                    Button("显示") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
            }
        }
        .padding(24)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

struct SettingsDiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mihomo: MihomoManager
    @State private var portText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置与诊断").font(.largeTitle.bold())
                GroupBox("Mihomo") {
                    Form {
                        Picker("核心来源", selection: $model.configuration.mihomoSource) {
                            ForEach(MihomoSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        Text("当前路径：\(model.resolvedMihomo?.path ?? "未找到")")
                            .font(.caption).textSelection(.enabled)
                        HStack {
                            Button("安装/重新安装托管版") { Task { await model.installManagedMihomo() } }
                            Button("检查生成配置") { Task { await model.validateMihomo() } }
                                .help("只验证应用生成的 Mihomo YAML，不测试节点网络，也不改变 Mihomo 运行状态")
                        }
                        Text("“检查生成配置”只检查 YAML 是否能被 Mihomo 解析；代理是否可用请在概览中运行“测试代理连通性”。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }

                GroupBox("代理出口网络") {
                    Form {
                        Picker("出口方式", selection: Binding<String>(
                            get: { model.configuration.preferredUSBServiceID ?? "" },
                            set: { value in
                                Task { await model.setPreferredUSBServiceID(value.isEmpty ? nil : value) }
                            }
                        )) {
                            Text("系统自动").tag("")
                            ForEach(model.outboundSnapshot.services) { service in
                                Text("优先 \(service.name)\(service.interfaceName.map { "（\($0)）" } ?? "")")
                                    .tag(service.id)
                            }
                            if let selected = model.configuration.preferredUSBServiceID,
                               !model.outboundSnapshot.services.contains(where: { $0.id == selected }) {
                                Text("已选 USB 服务暂不可见").tag(selected)
                            }
                        }
                        HStack {
                            Text(model.outboundStatusText)
                                .textSelection(.enabled)
                            Spacer()
                            Button("重新检测") { Task { await model.refreshOutboundNetwork(force: true) } }
                                .disabled(model.isBusy)
                        }
                        if let reason = model.outboundSnapshot.fallbackReason {
                            Text("已撤销 USB 出口绑定；系统默认出口：\(model.outboundSnapshot.defaultNetworkName)。原因：\(reason)")
                                .foregroundStyle(.orange)
                        }
                        Text("USB 与 Wi-Fi 同时使用时，请在 macOS 网络设置中关闭该 USB 服务的“需要时启用”。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }

                GroupBox("本地端口与输出") {
                    Form {
                        HStack {
                            Text("SOCKS5 端口")
                            TextField("例如 17892", text: $portText)
                                .labelsHidden()
                                .monospacedDigit()
                                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
                            Button("保存端口") { savePort() }
                            Spacer()
                        }
                        HStack {
                            Text("输出目录")
                            Text(model.outputDirectory.path).lineLimit(1).textSelection(.enabled)
                            Spacer()
                            Button("选择…") { chooseOutputDirectory() }
                            if model.configuration.outputDirectory != nil {
                                Button("恢复默认") {
                                    model.configuration.outputDirectory = nil
                                    Task { await model.saveConfiguration() }
                                }
                            }
                        }
                    }
                    .padding(6)
                }

                GroupBox("应用") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("登录时启动", isOn: Binding(
                            get: { model.configuration.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        HStack {
                            Button("导出 .msbridge") { exportConfiguration() }
                            Button("导入并替换配置") { importConfiguration() }
                            Button("打开数据目录") { NSWorkspace.shared.open(model.paths.root) }
                            Button("打开日志目录") { NSWorkspace.shared.open(model.paths.logs) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("诊断") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mihomo：\(mihomo.state.label)")
                        Text("有效节点：\(model.currentNodes.count)")
                        Text("更新频率：每 1 小时")
                        Text("状态：\(model.statusMessage)").textSelection(.enabled)
                        Text("代理出口：\(model.outboundStatusText)").textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                Button("保存设置") { Task { await model.saveConfiguration() } }
                    .buttonStyle(.borderedProminent)
                HStack(spacing: 8) {
                    Text(appVersionDescription)
                    Link("github.com/vengence/MihomoSurgeBridge",
                         destination: URL(string: "https://github.com/vengence/MihomoSurgeBridge")!)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .onAppear { portText = model.configuration.socksPort.map(String.init) ?? "" }
    }

    private func savePort() {
        guard let port = UInt16(portText), PortChecker.isAvailable(port) else {
            model.statusMessage = "端口无效或已被占用；正在运行时请先停止 Mihomo"
            return
        }
        model.configuration.socksPort = port
        Task { await model.saveConfiguration() }
    }

    private var appVersionDescription: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return "MihomoSurgeBridge 开发版本"
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "MihomoSurgeBridge \(version)（构建 \(build)）"
        }
        return "MihomoSurgeBridge \(version)"
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.configuration.outputDirectory = url.path
            Task { await model.saveConfiguration() }
        }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MihomoSurgeBridge.msbridge"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try model.exportConfiguration(to: url)
                model.statusMessage = "配置已导出；文件中包含订阅 URL"
            } catch { model.statusMessage = error.localizedDescription }
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do { try await model.importConfiguration(from: url) }
                catch { model.statusMessage = error.localizedDescription }
            }
        }
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mihomo: MihomoManager

    var body: some View {
        Text(mihomo.state.label)
        Text("SSR 节点：\(model.currentNodes.count)")
        Divider()
        Button("打开管理窗口") {
            _ = NSApplication.shared.setActivationPolicy(.regular)
            openWindow(id: "main")
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        if mihomo.state.isRunning {
            Button("停止 Mihomo") { Task { await model.stopMihomo() } }
        } else {
            Button("启动 Mihomo") { Task { await model.startMihomo() } }
        }
        Button("立即更新全部") { Task { await model.refreshAll() } }
        Divider()
        Button("退出应用") { Task { await model.quitApplication() } }
    }
}
