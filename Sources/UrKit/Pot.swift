import Foundation

/// A pot is one independent instance of an ur app: its own config, slip scripts, website data,
/// socket, and (optionally) LaunchAgent. One clay body (the app), many pots.
///
///   config   $UR_CONFIG_HOME/<app>/<pot>/config.json   (default ~/.config/ur)
///   slip     $UR_CONFIG_HOME/<app>/<pot>/slip/
///   socket   $UR_RUN_DIR/<app>/<pot>.sock              (default ~/Library/Application Support/Ur/run)
///   agent    ~/Library/LaunchAgents/io.ur.<app>.<pot>.plist
///
/// The two environment overrides exist so tests can run fully isolated pots.
public struct Pot: Equatable {
    public static let defaultName = "default"

    public let app: String
    public let name: String

    public init(app: String, name: String) {
        self.app = app
        self.name = name
    }

    /// Letters, digits, `-` and `_`; must start with a letter or digit; at most 40 characters.
    /// Keeps socket paths under the 104-byte `sun_path` limit and names safe in URLs and plists.
    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.count <= 40 else { return false }
        let alnum = CharacterSet.alphanumerics
        guard first.isASCII, alnum.contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { $0.isASCII && (alnum.contains($0) || $0 == "-" || $0 == "_") }
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func envURL(_ key: String) -> URL? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    public static func configRoot(app: String) -> URL {
        (envURL("UR_CONFIG_HOME") ?? home.appendingPathComponent(".config/ur", isDirectory: true))
            .appendingPathComponent(app, isDirectory: true)
    }

    public static func runRoot(app: String) -> URL {
        (envURL("UR_RUN_DIR") ?? home.appendingPathComponent("Library/Application Support/Ur/run", isDirectory: true))
            .appendingPathComponent(app, isDirectory: true)
    }

    public var directory: URL { Pot.configRoot(app: app).appendingPathComponent(name, isDirectory: true) }
    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var slipDirectory: URL { directory.appendingPathComponent("slip", isDirectory: true) }
    public var socketURL: URL { Pot.runRoot(app: app).appendingPathComponent("\(name).sock") }
    public var launchAgentLabel: String { "io.ur.\(app).\(name)" }
    public var launchAgentURL: URL {
        Pot.home.appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    /// Stable per-pot UUID (name-based, RFC 4122 v5-style layout over a FNV-1a digest).
    /// Used for per-pot storage identifiers such as `WKWebsiteDataStore(forIdentifier:)`.
    public var storageIdentifier: UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let seed = Array("ur.\(app).\(name)".utf8)
        // Two independent 64-bit FNV-1a passes → 128 bits. Not cryptographic; just stable.
        func fnv(_ salt: UInt64) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325 ^ salt
            for b in seed { h ^= UInt64(b); h = h &* 0x100000001b3 }
            return h
        }
        let a = fnv(0), b = fnv(0x9e3779b97f4a7c15)
        for i in 0..<8 { bytes[i] = UInt8((a >> (UInt64(i) * 8)) & 0xff) }
        for i in 0..<8 { bytes[8 + i] = UInt8((b >> (UInt64(i) * 8)) & 0xff) }
        bytes[6] = (bytes[6] & 0x0f) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3f) | 0x80  // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Every pot with a config folder or a socket, sorted by name.
    public static func all(app: String) -> [String] {
        let fm = FileManager.default
        var names = Set<String>()
        if let dirs = try? fm.contentsOfDirectory(atPath: configRoot(app: app).path) {
            for d in dirs where isValidName(d) {
                if fm.fileExists(atPath: configRoot(app: app).appendingPathComponent(d).appendingPathComponent("config.json").path) {
                    names.insert(d)
                }
            }
        }
        if let socks = try? fm.contentsOfDirectory(atPath: runRoot(app: app).path) {
            for s in socks where s.hasSuffix(".sock") {
                let n = String(s.dropLast(5))
                if isValidName(n) { names.insert(n) }
            }
        }
        return names.sorted()
    }

    public var isRunning: Bool { IPCClient.isListening(socketURL) }
}
