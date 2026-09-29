import Foundation

public struct MigrationDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var subscriptions: [MigrationSubscription]
    public var regions: [RegionConfiguration]
    public var updateIntervalSeconds: Int
    public var desiredMihomoRunning: Bool

    public init(configuration: AppConfiguration, exportedAt: Date = Date()) {
        schemaVersion = 1
        self.exportedAt = exportedAt
        subscriptions = configuration.subscriptions.map(MigrationSubscription.init)
        regions = configuration.regions
        updateIntervalSeconds = configuration.updateIntervalSeconds
        desiredMihomoRunning = configuration.desiredMihomoRunning
    }

    public func applying(to configuration: AppConfiguration = .init()) -> AppConfiguration {
        var result = configuration
        result.schemaVersion = 1
        result.subscriptions = subscriptions.map(SubscriptionConfiguration.init)
        result.regions = regions
        result.updateIntervalSeconds = updateIntervalSeconds
        result.desiredMihomoRunning = desiredMihomoRunning
        result.socksPort = nil
        result.outputDirectory = nil
        result.mihomoSource = .automatic
        result.preferredUSBServiceID = nil
        return result
    }
}

public struct MigrationSubscription: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var isEnabled: Bool
    public var autoUpdate: Bool
    public var includeKeywords: [String]
    public var excludeKeywords: [String]
    public var namePrefix: String
    public var nameSuffix: String

    public init(_ source: SubscriptionConfiguration) {
        id = source.id
        name = source.name
        url = source.url
        isEnabled = source.isEnabled
        autoUpdate = source.autoUpdate
        includeKeywords = source.includeKeywords
        excludeKeywords = source.excludeKeywords
        namePrefix = source.namePrefix
        nameSuffix = source.nameSuffix
    }
}

private extension SubscriptionConfiguration {
    init(_ source: MigrationSubscription) {
        self.init(
            id: source.id,
            name: source.name,
            url: source.url,
            isEnabled: source.isEnabled,
            autoUpdate: source.autoUpdate,
            includeKeywords: source.includeKeywords,
            excludeKeywords: source.excludeKeywords,
            namePrefix: source.namePrefix,
            nameSuffix: source.nameSuffix
        )
    }
}
