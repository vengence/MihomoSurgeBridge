import Darwin
import Foundation
import IOKit
import Network
import SystemConfiguration

struct USBNetworkService: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let interfaceName: String?
    let isEnabled: Bool
}

struct OutboundNetworkSnapshot: Equatable, Sendable {
    let services: [USBNetworkService]
    let preferredServiceName: String?
    let interfaceName: String?
    let fallbackReason: String?
    let defaultNetworkName: String

    var targetDescription: String {
        if let interfaceName {
            return "USB：\(preferredServiceName ?? "已选择的服务")（\(interfaceName)）"
        }
        return "系统默认：\(defaultNetworkName)"
    }
}

enum OutboundNetworkDetector {
    static func inspect(preferredServiceID: String?) -> OutboundNetworkSnapshot {
        let allServices = configuredServices()
        let usbServices = allServices.filter { service in
            guard let interfaceName = service.interfaceName else { return false }
            return isUSBHardware(interfaceName)
        }
        let defaultName = defaultNetworkName(allServices: allServices)
        guard let preferredServiceID else {
            return .init(services: usbServices, preferredServiceName: nil,
                         interfaceName: nil, fallbackReason: nil, defaultNetworkName: defaultName)
        }
        guard let selected = allServices.first(where: { $0.id == preferredServiceID }) else {
            return .init(services: usbServices, preferredServiceName: nil,
                         interfaceName: nil, fallbackReason: "所选 USB 网络服务未找到",
                         defaultNetworkName: defaultName)
        }
        let name = selected.name
        func fallback(_ reason: String) -> OutboundNetworkSnapshot {
            .init(services: usbServices, preferredServiceName: name,
                  interfaceName: nil, fallbackReason: reason, defaultNetworkName: defaultName)
        }
        guard selected.isEnabled else {
            return fallback("USB 网络服务已停用；请检查 macOS 网络设置中的“需要时启用”")
        }
        guard let interfaceName = selected.interfaceName, isUSBHardware(interfaceName) else {
            return fallback("USB 网络未连接或网卡未出现")
        }
        let families = usableAddressFamilies(interfaceName)
        guard !families.isEmpty else { return fallback("USB 网络未取得可用 IP") }
        let routedFamilies = families.filter { hasScopedRoute(interfaceName, family: $0) }
        guard !routedFamilies.isEmpty else { return fallback("USB 网络没有外网路由") }
        guard routedFamilies.contains(where: { probe(interfaceName, family: $0) }) else {
            return fallback("USB 网络无法访问外网")
        }
        return .init(services: usbServices, preferredServiceName: name,
                     interfaceName: interfaceName, fallbackReason: nil,
                     defaultNetworkName: defaultName)
    }

    private static func configuredServices() -> [USBNetworkService] {
        guard let preferences = SCPreferencesCreate(nil, "MihomoSurgeBridge" as CFString, nil),
              let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else { return [] }
        return services.compactMap { service in
            guard let id = SCNetworkServiceGetServiceID(service) as String? else { return nil }
            let networkInterface = SCNetworkServiceGetInterface(service)
            return USBNetworkService(
                id: id,
                name: (SCNetworkServiceGetName(service) as String?) ?? "未命名网络",
                interfaceName: networkInterface.flatMap { SCNetworkInterfaceGetBSDName($0) as String? },
                isEnabled: SCNetworkServiceGetEnabled(service)
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isUSBHardware(_ bsdName: String) -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IONetworkInterface"),
                                           &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let registeredName = IORegistryEntryCreateCFProperty(
                entry, "BSD Name" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String
            guard registeredName == bsdName else { continue }
            var parent: io_registry_entry_t = entry
            var ownsParent = false
            defer { if ownsParent { IOObjectRelease(parent) } }
            while true {
                if IOObjectConformsTo(parent, "IOUSBHostDevice") != 0 ||
                    IOObjectConformsTo(parent, "IOUSBHostInterface") != 0 ||
                    IOObjectConformsTo(parent, "IOUSBDevice") != 0 { return true }
                var next: io_registry_entry_t = 0
                guard IORegistryEntryGetParentEntry(parent, kIOServicePlane, &next) == KERN_SUCCESS else {
                    break
                }
                if ownsParent { IOObjectRelease(parent) }
                parent = next
                ownsParent = true
            }
        }
        return false
    }

    private enum AddressFamily: Hashable {
        case ipv4, ipv6
        var target: String { self == .ipv4 ? "1.1.1.1" : "2606:4700:4700::1111" }
        var routeFlag: String { self == .ipv4 ? "-inet" : "-inet6" }
    }

    private static func usableAddressFamilies(_ bsdName: String) -> Set<AddressFamily> {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var result: Set<AddressFamily> = []
        var current = first
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard String(cString: item.pointee.ifa_name) == bsdName,
                  item.pointee.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  let address = item.pointee.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host,
                              socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
                .lowercased()
            if family == AF_INET {
                if !ip.hasPrefix("169.254.") && !ip.hasPrefix("127.") && ip != "0.0.0.0" {
                    result.insert(.ipv4)
                }
            } else if !ip.hasPrefix("fe80:") && ip != "::1" && ip != "::" {
                result.insert(.ipv6)
            }
        }
        return result
    }

    private static func hasScopedRoute(_ bsdName: String, family: AddressFamily) -> Bool {
        guard let result = try? ProcessRunner.run(
            URL(fileURLWithPath: "/sbin/route"),
            arguments: ["-n", "get", family.routeFlag, "-ifscope", bsdName, family.target]
        ), result.status == 0 else { return false }
        return result.output.split(whereSeparator: \.isNewline).contains { line in
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            return parts.count == 2 && parts[0] == "interface" && parts[1] == bsdName
        }
    }

    private static func probe(_ bsdName: String, family: AddressFamily) -> Bool {
        let version = family == .ipv4 ? "-4" : "-6"
        for url in ["https://cp.cloudflare.com/generate_204",
                    "https://www.apple.com/library/test/success.html"] {
            let result = try? ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: ["--noproxy", "*", "--interface", "if!\(bsdName)", version,
                            "--connect-timeout", "3", "--max-time", "5", "--silent",
                            "--output", "/dev/null", url]
            )
            if result?.status == 0 { return true }
        }
        return false
    }

    private static func defaultNetworkName(allServices: [USBNetworkService]) -> String {
        guard let store = SCDynamicStoreCreate(nil, "MihomoSurgeBridge" as CFString, nil, nil),
              let state = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any],
              let name = state["PrimaryInterface"] as? String else { return "系统默认网络" }
        let service = allServices.first { $0.interfaceName == name }
        return "\(service?.name ?? name)（\(name)）"
    }
}

@MainActor
final class OutboundNetworkObserver {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "MihomoSurgeBridge.network-path")
    private var timer: Task<Void, Never>?

    func start(onChange: @escaping @MainActor () -> Void) {
        monitor.pathUpdateHandler = { _ in Task { @MainActor in onChange() } }
        monitor.start(queue: queue)
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                onChange()
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        monitor.cancel()
    }
}
