import Foundation

/// Reply to a `Request`. `text` is what a human sees; `data` is what `--json` prints.
public struct Response: Codable, Equatable {
    public var ok: Bool
    public var error: String?
    public var text: String?
    public var data: JSONValue?

    public init(ok: Bool, error: String? = nil, text: String? = nil, data: JSONValue? = nil) {
        self.ok = ok; self.error = error; self.text = text; self.data = data
    }

    public static func success(text: String? = nil) -> Response {
        Response(ok: true, text: text)
    }

    public static func success<T: Encodable>(_ value: T, text: String? = nil) -> Response {
        do {
            return Response(ok: true, text: text, data: try JSONValue(encoding: value))
        } catch {
            return .failure("could not encode reply: \(error)")
        }
    }

    public static func failure(_ message: String) -> Response {
        Response(ok: false, error: message)
    }
}

/// Untyped JSON, so replies can carry any Encodable payload across the socket.
public enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        self = .object(try c.decode([String: JSONValue].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let b):   try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public init<T: Encodable>(encoding value: T) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b):   return String(b)
        default:             return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public func prettyString() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(self), let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }
}
