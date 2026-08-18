import Foundation

public enum MihomoSource: String, Codable, CaseIterable, Sendable {
    case automatic
    case homebrew
    case managed

    public var displayName: String {
        switch self {
        case .automatic: "自动检测"
        case .homebrew: "Homebrew"
        case .managed: "应用托管"
        }
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var subscriptions: [SubscriptionConfiguration]
    public var regions: [RegionConfiguration]
    public var updateIntervalSeconds: Int
    public var mihomoSource: MihomoSource
    public var socksPort: UInt16?
    public var outputDirectory: String?
    public var launchAtLogin: Bool
    public var desiredMihomoRunning: Bool
    public var lastScheduledRefreshAt: Date?

    public init(
        schemaVersion: Int = 1,
        subscriptions: [SubscriptionConfiguration] = [],
        regions: [RegionConfiguration] = RegionConfiguration.defaults,
        updateIntervalSeconds: Int = 3_600,
        mihomoSource: MihomoSource = .automatic,
        socksPort: UInt16? = nil,
        outputDirectory: String? = nil,
        launchAtLogin: Bool = false,
        desiredMihomoRunning: Bool = false,
        lastScheduledRefreshAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.subscriptions = subscriptions
        self.regions = regions
        self.updateIntervalSeconds = updateIntervalSeconds
        self.mihomoSource = mihomoSource
        self.socksPort = socksPort
        self.outputDirectory = outputDirectory
        self.launchAtLogin = launchAtLogin
        self.desiredMihomoRunning = desiredMihomoRunning
        self.lastScheduledRefreshAt = lastScheduledRefreshAt
    }
}

public struct SubscriptionConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var isEnabled: Bool
    public var autoUpdate: Bool
    public var includeKeywords: [String]
    public var excludeKeywords: [String]
    public var namePrefix: String
    public var nameSuffix: String
    public var lastSuccessfulUpdate: Date?
    public var lastError: String?
    public var rawNodeCount: Int
    public var filteredNodeCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        isEnabled: Bool = true,
        autoUpdate: Bool = true,
        includeKeywords: [String] = [],
        excludeKeywords: [String] = [],
        namePrefix: String? = nil,
        nameSuffix: String = "",
        lastSuccessfulUpdate: Date? = nil,
        lastError: String? = nil,
        rawNodeCount: Int = 0,
        filteredNodeCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.autoUpdate = autoUpdate
        self.includeKeywords = includeKeywords
        self.excludeKeywords = excludeKeywords
        self.namePrefix = namePrefix ?? "\(name) · "
        self.nameSuffix = nameSuffix
        self.lastSuccessfulUpdate = lastSuccessfulUpdate
        self.lastError = lastError
        self.rawNodeCount = rawNodeCount
        self.filteredNodeCount = filteredNodeCount
    }
}

public struct RegionConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var keywords: [String]

    public init(id: String, name: String, keywords: [String]) {
        self.id = id
        self.name = name
        self.keywords = keywords
    }

    public static let defaults: [RegionConfiguration] = [
        .init(id: "hk", name: "香港", keywords: ["🇭🇰", "香港", "Hong Kong", "HK"]),
        .init(id: "jp", name: "日本", keywords: ["🇯🇵", "日本", "Japan", "JP"]),
        .init(id: "sg", name: "新加坡", keywords: ["🇸🇬", "新加坡", "Singapore", "SG"]),
        .init(id: "tw", name: "台湾", keywords: ["🇹🇼", "🇨🇳", "台湾", "Taiwan", "TW"]),
        .init(id: "us", name: "美国", keywords: ["🇺🇸", "🇺🇲", "美国", "United States", "US"])
    ]
}

public struct RawSSRNode: Equatable, Sendable {
    public var subscriptionID: UUID
    public var originalName: String
    public var fields: [String: YAMLValue]

    public init(subscriptionID: UUID, originalName: String, fields: [String: YAMLValue]) {
        self.subscriptionID = subscriptionID
        self.originalName = originalName
        self.fields = fields
    }
}

public struct RoutedSSRNode: Identifiable, Equatable, Sendable {
    public var id: String { identity }
    public var identity: String
    public var subscriptionID: UUID
    public var originalName: String
    public var displayName: String
    public var internalName: String
    public var username: String
    public var password: String
    public var fields: [String: YAMLValue]

    public init(
        identity: String,
        subscriptionID: UUID,
        originalName: String,
        displayName: String,
        internalName: String,
        username: String,
        password: String,
        fields: [String: YAMLValue]
    ) {
        self.identity = identity
        self.subscriptionID = subscriptionID
        self.originalName = originalName
        self.displayName = displayName
        self.internalName = internalName
        self.username = username
        self.password = password
        self.fields = fields
    }
}

public struct ProcessedSubscription: Sendable {
    public var subscription: SubscriptionConfiguration
    public var rawCount: Int
    public var nodes: [RoutedSSRNode]

    public init(subscription: SubscriptionConfiguration, rawCount: Int, nodes: [RoutedSSRNode]) {
        self.subscription = subscription
        self.rawCount = rawCount
        self.nodes = nodes
    }
}

public struct SurgeOutputBundle: Sendable {
    public var files: [String: String]
    public var groupLines: [String]

    public init(files: [String: String], groupLines: [String]) {
        self.files = files
        self.groupLines = groupLines
    }

    public var completeProxyGroupBlock: String {
        (["[Proxy Group]"] + groupLines).joined(separator: "\n") + "\n"
    }
}
