import Foundation

/// One addressed command for one pot of one ur app: `<app> [pot] <verb> [args…] [--key value…]`.
///
/// Every control surface — CLI argv, `<scheme>://` URLs, and the socket wire format — parses
/// into this single shape, so an app implements each verb exactly once.
public struct Request: Codable, Equatable {
    public var pot: String
    public var verb: String
    public var args: [String]
    public var options: [String: String]

    public init(pot: String = Pot.defaultName, verb: String, args: [String] = [], options: [String: String] = [:]) {
        self.pot = pot; self.verb = verb; self.args = args; self.options = options
    }

    /// `options[key]`, treating an empty string as absent.
    public func option(_ key: String) -> String? {
        guard let v = options[key], !v.isEmpty else { return nil }
        return v
    }

    public func flag(_ key: String) -> Bool {
        guard let v = options[key]?.lowercased() else { return false }
        return v == "true" || v == "1" || v == "yes" || v.isEmpty
    }
}

public struct UrError: Error, CustomStringConvertible, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

public enum RequestParser {
    /// Splits leading words into pot + verb. A first word that is a known verb addresses the
    /// default pot (`ur-browse toggle`); anything else is a pot name (`ur-browse work toggle`).
    public static func split(words: [String], verbs: Set<String>, defaultVerb: String) -> (pot: String, verb: String, args: [String]) {
        guard let first = words.first else { return (Pot.defaultName, defaultVerb, []) }
        if verbs.contains(first) { return (Pot.defaultName, first, Array(words.dropFirst())) }
        let rest = Array(words.dropFirst())
        guard let verb = rest.first else { return (first, defaultVerb, []) }
        return (first, verb, Array(rest.dropFirst()))
    }

    /// CLI argv (without the program name). Options are `--key value`, `--key=value`, or a bare
    /// `--flag` when `flag` is in `booleanFlags`.
    public static func parse(argv: [String], verbs: Set<String>, booleanFlags: Set<String> = [],
                             defaultVerb: String) throws -> Request {
        var words: [String] = []
        var options: [String: String] = [:]
        var i = 0
        while i < argv.count {
            let arg = argv[i]
            if arg == "--" {
                words.append(contentsOf: argv[(i + 1)...])
                break
            }
            if arg.hasPrefix("--"), arg.count > 2 {
                let body = String(arg.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    options[String(body[..<eq])] = String(body[body.index(after: eq)...])
                } else if booleanFlags.contains(body) {
                    options[body] = "true"
                } else {
                    i += 1
                    guard i < argv.count else { throw UrError("'--\(body)' requires a value") }
                    options[body] = argv[i]
                }
            } else {
                words.append(arg)
            }
            i += 1
        }
        let (pot, verb, args) = split(words: words, verbs: verbs, defaultVerb: defaultVerb)
        guard Pot.isValidName(pot) else { throw UrError("invalid pot name '\(pot)'") }
        return Request(pot: pot, verb: verb, args: args, options: options)
    }

    /// `<scheme>://[pot/]verb[/arg…][?key=value…]`. Path segments are percent-decoded.
    /// Returns nil when the URL's scheme is not in `schemes`.
    public static func parse(url: URL, schemes: Set<String>, verbs: Set<String>, defaultVerb: String) -> Request? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var words: [String] = []
        if let host = comps?.host, !host.isEmpty { words.append(host.removingPercentEncoding ?? host) }
        words += url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        var options: [String: String] = [:]
        for item in comps?.queryItems ?? [] { options[item.name] = item.value ?? "true" }
        let (pot, verb, args) = split(words: words, verbs: verbs, defaultVerb: defaultVerb)
        guard Pot.isValidName(pot) else { return nil }
        return Request(pot: pot, verb: verb, args: args, options: options)
    }
}
