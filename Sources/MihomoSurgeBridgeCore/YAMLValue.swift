import Foundation

public enum YAMLValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case array([YAMLValue])
    case object([String: YAMLValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([YAMLValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: YAMLValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "不支持的 YAML 值")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public static func convert(_ value: Any) throws -> YAMLValue {
        if value is NSNull { return .null }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? Int { return .integer(value) }
        if let value = value as? Double { return .double(value) }
        if let value = value as? String { return .string(value) }
        if let value = value as? [Any] {
            return .array(try value.map(convert))
        }
        if let value = value as? [String: Any] {
            return .object(try value.mapValues(convert))
        }
        if let value = value as? [AnyHashable: Any] {
            var result: [String: YAMLValue] = [:]
            for (key, item) in value {
                guard let key = key as? String else { continue }
                result[key] = try convert(item)
            }
            return .object(result)
        }
        throw YAMLValueError.unsupportedValue(String(describing: type(of: value)))
    }

    public var anyValue: Any {
        switch self {
        case let .string(value): value
        case let .integer(value): value
        case let .double(value): value
        case let .bool(value): value
        case let .array(value): value.map(\.anyValue)
        case let .object(value): value.mapValues(\.anyValue)
        case .null: NSNull()
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case let .integer(value): value
        case let .double(value): Int(value)
        case let .string(value): Int(value)
        default: nil
        }
    }
}

public enum YAMLValueError: LocalizedError {
    case unsupportedValue(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedValue(type): "不支持的 YAML 值类型：\(type)"
        }
    }
}
