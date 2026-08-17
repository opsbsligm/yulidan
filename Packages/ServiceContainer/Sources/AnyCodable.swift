import Foundation

/// 任何可编码值的包装器
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
            return
        }

        if let bool = try? container.decode(Bool.self) {
            value = bool
            return
        }

        if let int = try? container.decode(Int.self) {
            value = int
            return
        }

        if let double = try? container.decode(Double.self) {
            value = double
            return
        }

        if let string = try? container.decode(String.self) {
            value = string
            return
        }

        if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
            return
        }

        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
            return
        }

        value = NSNull()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            let anyCodableArray = array.map { AnyCodable($0) }
            try container.encode(anyCodableArray)
        } else if let dict = value as? [String: Any] {
            let anyCodableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(anyCodableDict)
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

extension AnyCodable: CustomStringConvertible {
    public var description: String {
        switch value {
        case let v as Bool: "\(v)"
        case let v as Int: "\(v)"
        case let v as Double: "\(v)"
        case let v as String: v
        default: String(describing: value)
        }
    }
}
