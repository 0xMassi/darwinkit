import Foundation

// MARK: - JSON-RPC 2.0 Message Types

public struct JsonRpcRequest: Codable {
    public let jsonrpc: String
    public let id: String?
    public let method: String
    public let params: [String: AnyCodable]?

    public init(id: String?, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    /// Get a string param or nil
    public func string(_ key: String) -> String? {
        params?[key]?.stringValue
    }

    /// Get a string param or throw
    public func requireString(_ key: String) throws -> String {
        guard let value = string(key) else {
            throw JsonRpcError.invalidParams("Missing required param: \(key)")
        }
        return value
    }

    /// Get a string array param or default
    public func stringArray(_ key: String) -> [String]? {
        params?[key]?.stringArrayValue
    }

    /// Get an int param or nil
    public func int(_ key: String) -> Int? {
        params?[key]?.intValue
    }

    /// Get a double param or nil
    public func double(_ key: String) -> Double? {
        params?[key]?.doubleValue
    }

    /// Get a bool param or nil
    public func bool(_ key: String) -> Bool? {
        params?[key]?.boolValue
    }
}

public struct JsonRpcResponse: Codable {
    public let jsonrpc: String
    public let id: String?
    public let result: AnyCodable?
    public let error: JsonRpcErrorBody?

    public static func success(id: String?, result: Any) -> JsonRpcResponse {
        JsonRpcResponse(jsonrpc: "2.0", id: id, result: AnyCodable(result), error: nil)
    }

    public static func failure(id: String?, error: JsonRpcError) -> JsonRpcResponse {
        JsonRpcResponse(jsonrpc: "2.0", id: id, result: nil, error: error.body)
    }

    public static func notification(method: String, params: Any) -> JsonRpcResponse {
        JsonRpcResponse(jsonrpc: "2.0", id: nil, result: AnyCodable(["method": method, "params": params]), error: nil)
    }
}

public struct JsonRpcErrorBody: Codable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: Any? = nil) {
        self.code = code
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }
}

// MARK: - Error Types

public enum JsonRpcError: Error {
    case parseError(String)
    case invalidRequest(String)
    case methodNotFound(String)
    case invalidParams(String)
    case frameworkUnavailable(String)
    case permissionDenied(String)
    case osVersionTooOld(String)
    case operationCancelled
    case internalError(String)

    public var body: JsonRpcErrorBody {
        switch self {
        case .parseError(let msg):
            return JsonRpcErrorBody(code: -32700, message: msg)
        case .invalidRequest(let msg):
            return JsonRpcErrorBody(code: -32600, message: msg)
        case .methodNotFound(let msg):
            return JsonRpcErrorBody(code: -32601, message: msg)
        case .invalidParams(let msg):
            return JsonRpcErrorBody(code: -32602, message: msg)
        case .frameworkUnavailable(let msg):
            return JsonRpcErrorBody(code: -32001, message: msg)
        case .permissionDenied(let msg):
            return JsonRpcErrorBody(code: -32002, message: msg)
        case .osVersionTooOld(let msg):
            return JsonRpcErrorBody(code: -32003, message: msg)
        case .operationCancelled:
            return JsonRpcErrorBody(code: -32004, message: "Operation cancelled")
        case .internalError(let msg):
            return JsonRpcErrorBody(code: -32603, message: msg)
        }
    }
}

// MARK: - AnyCodable (type-erased Codable wrapper)

public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public var stringValue: String? { value as? String }
    public var intValue: Int? { value as? Int }
    public var doubleValue: Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
    public var boolValue: Bool? { value as? Bool }
    public var arrayValue: [Any]? { value as? [Any] }
    public var dictValue: [String: Any]? { value as? [String: Any] }
    public var stringArrayValue: [String]? { value as? [String] }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int64 as Int64:
            try container.encode(int64)
        case let float as Float:
            try container.encode(float)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}
