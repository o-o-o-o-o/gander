import Foundation

/// Everything an Ur app's CLI needs to know about its app. The CLI itself is generic:
/// `UrCLI(spec).run()` handles pot routing, the socket round-trip, output formats, and the
/// pot-management verbs every Ur app shares (`pots`, `throw`, `start`, `help`).
public struct UrAppSpec {
    public var app: String               // "browse" — pot paths, socket dir, LaunchAgent label
    public var command: String           // "ur-browse" — shown in messages
    public var bundleID: String          // "io.ur.browse"
    public var appExecutable: String     // executable name inside the .app ("UrBrowse")
    public var devExecutable: String     // SwiftPM product next to the CLI in .build ("UrBrowseApp")
    public var installedAppPath: String  // "/Applications/Ur Browse.app"
    public var schemes: Set<String>      // URL schemes the app accepts
    public var verbs: Set<String>        // verbs the app answers over the socket
    public var booleanFlags: Set<String> // options that take no value
    public var defaultVerb: String
    /// Verbs that start a stopped pot before sending (e.g. `open`), so automation never has to
    /// care whether the pot is already running.
    public var autostartVerbs: Set<String>
    /// `throw --<option> value` → config key, e.g. ["glaze": "glaze", "url": "defaultUrl"].
    public var throwOptions: [String: String]
    public var usage: String

    public init(app: String, command: String, bundleID: String, appExecutable: String,
                devExecutable: String, installedAppPath: String, schemes: Set<String>,
                verbs: Set<String>, booleanFlags: Set<String>, defaultVerb: String,
                autostartVerbs: Set<String>, throwOptions: [String: String], usage: String) {
        self.app = app; self.command = command; self.bundleID = bundleID
        self.appExecutable = appExecutable; self.devExecutable = devExecutable
        self.installedAppPath = installedAppPath; self.schemes = schemes; self.verbs = verbs
        self.booleanFlags = booleanFlags; self.defaultVerb = defaultVerb
        self.autostartVerbs = autostartVerbs; self.throwOptions = throwOptions; self.usage = usage
    }

    /// Verbs the CLI handles itself, without a running app. Also reserved as pot names.
    public static let localVerbs: Set<String> = ["help", "pots", "throw", "start"]
    /// Output-format flags, translated into the `format` option before sending.
    public static let formatFlags: Set<String> = ["json", "alfred"]

    public var allVerbs: Set<String> { verbs.union(UrAppSpec.localVerbs) }

    public func pot(_ name: String) -> Pot { Pot(app: app, name: name) }
}

public struct UrCLI {
    public let spec: UrAppSpec

    public init(_ spec: UrAppSpec) { self.spec = spec }

    public func run(_ argv: [String] = Array(CommandLine.arguments.dropFirst())) -> Never {
        do {
            let request = try RequestParser.parse(
                argv: argv, verbs: spec.allVerbs,
                booleanFlags: spec.booleanFlags.union(UrAppSpec.formatFlags).union(["login", "no-start", "help"]),
                defaultVerb: spec.defaultVerb)
            if request.flag("help") { print(spec.usage); exit(0) }
            switch request.verb {
            case "help":  print(spec.usage); exit(0)
            case "pots":  try listPots(request)
            case "throw": try throwPot(request)
            case "start": try startPot(request)
            default:      try send(request)
            }
            exit(0)
        } catch {
            fail("\(error)")
        }
    }

    // MARK: Sending

    private func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("\(spec.command): \(message)\n".utf8))
        exit(code)
    }

    private func send(_ original: Request) throws {
        var request = original
        let format = formatOption(&request)
        let pot = spec.pot(request.pot)

        if !pot.isRunning {
            guard spec.autostartVerbs.contains(request.verb) else {
                fail("pot '\(pot.name)' is not running — start it with: \(spec.command) \(pot.name) start", code: 2)
            }
            try launch(pot)
            try waitUntilRunning(pot)
        }

        let response = try IPCClient.send(request, to: pot.socketURL)
        guard response.ok else { fail(response.error ?? "failed") }
        output(response, format: format)
    }

    /// Strips --json / --alfred and records the choice as `format` (the app may shape replies by it).
    private func formatOption(_ request: inout Request) -> String? {
        var format = request.option("format")
        for f in UrAppSpec.formatFlags where request.flag(f) {
            format = f
            request.options.removeValue(forKey: f)
        }
        if let format { request.options["format"] = format }
        return format
    }

    private func output(_ response: Response, format: String?) {
        switch format {
        case "json":
            print((response.data ?? .object([:])).prettyString())
        case "alfred":
            print(Alfred.scriptFilter(response.data).prettyString())
        default:
            if let text = response.text, !text.isEmpty { print(text) }
            else if let data = response.data { print(data.prettyString()) }
        }
    }

    // MARK: pots

    private struct PotStatus: Encodable {
        let name: String
        let running: Bool
        let address: String
        let config: String
        let info: JSONValue?
    }

    private func listPots(_ original: Request) throws {
        var request = original
        let format = formatOption(&request)
        let scheme = spec.schemes.contains(spec.command) ? spec.command : (spec.schemes.sorted().first ?? spec.command)
        let statuses: [PotStatus] = Pot.all(app: spec.app).map { name in
            let pot = spec.pot(name)
            let running = pot.isRunning
            let info = running ? (try? IPCClient.send(Request(pot: name, verb: "info"), to: pot.socketURL, timeout: 2))?.data : nil
            return PotStatus(name: name, running: running, address: "\(scheme)://\(name)",
                             config: pot.configURL.path, info: info)
        }
        switch format {
        case "json":
            print(try JSONValue(encoding: statuses).prettyString())
        case "alfred":
            let items: [JSONValue] = statuses.map {
                .object(["uid": .string($0.name), "title": .string($0.name),
                         "subtitle": .string($0.running ? "running" : "stopped"),
                         "arg": .string($0.name)])
            }
            print(JSONValue.object(["items": .array(items)]).prettyString())
        default:
            if statuses.isEmpty {
                print("No pots yet. Create one with: \(spec.command) throw <name>")
            }
            for s in statuses {
                let glaze = s.info?["glaze"]?.stringValue.map { "  \($0)" } ?? ""
                print("\(s.running ? "●" : "○") \(s.name)\(s.running ? "" : "  (stopped)")\(glaze)")
            }
        }
    }

    // MARK: throw — create a new pot

    private func throwPot(_ request: Request) throws {
        guard let name = request.args.first ?? (request.pot == Pot.defaultName ? nil : request.pot) else {
            throw UrError("usage: \(spec.command) throw <name> [--from <pot>] [--login] [--no-start]")
        }
        guard Pot.isValidName(name) else { throw UrError("invalid pot name '\(name)' (letters, digits, - and _)") }
        guard !spec.allVerbs.contains(name) else { throw UrError("'\(name)' is a command name; pick another pot name") }
        let pot = spec.pot(name)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: pot.configURL.path) else {
            throw UrError("pot '\(name)' already exists at \(pot.configURL.path)")
        }

        var config: [String: Any] = [:]
        if let from = request.option("from") {
            let source = spec.pot(from).configURL
            guard let data = try? Data(contentsOf: source),
                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UrError("cannot read pot '\(from)' config at \(source.path)")
            }
            config = dict
        }
        config["name"] = name
        for (option, key) in spec.throwOptions {
            if let value = request.option(option) { config[key] = value }
        }

        try fm.createDirectory(at: pot.slipDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: pot.configURL)
        print("threw pot '\(name)' → \(pot.configURL.path)")

        if request.flag("login") {
            try installLaunchAgent(pot)
            print("  starts at login (\(pot.launchAgentURL.path))")
        } else if !request.flag("no-start") {
            try launch(pot)
            print("  started — try: \(spec.command) \(name) show")
        }
    }

    // MARK: start

    private func startPot(_ request: Request) throws {
        let name = request.args.first ?? request.pot
        guard Pot.isValidName(name) else { throw UrError("invalid pot name '\(name)'") }
        let pot = spec.pot(name)
        if request.flag("login") {
            // Works for existing pots too (e.g. ones migrated from an older version).
            try installLaunchAgent(pot)
            print("pot '\(name)' starts at login (\(pot.launchAgentURL.path))")
            if !pot.isRunning { try waitUntilRunning(pot) }
            return
        }
        if pot.isRunning { print("pot '\(name)' is already running"); return }
        try launch(pot)
        try waitUntilRunning(pot)
        print("started pot '\(name)'")
    }

    // MARK: Launching

    /// The .app this CLI lives in (Homebrew symlinks the CLI out of Contents/MacOS), if any.
    private var enclosingAppBundle: URL? {
        let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let macOS = exe.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let bundle = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              bundle.pathExtension == "app" else { return nil }
        return bundle
    }

    /// The SwiftPM-built app binary next to a dev-build CLI (.build/release/), if any.
    private var devAppBinary: URL? {
        let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let candidate = exe.deletingLastPathComponent().appendingPathComponent(spec.devExecutable)
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private var appExecutablePath: String {
        if let bundle = enclosingAppBundle {
            return bundle.appendingPathComponent("Contents/MacOS/\(spec.appExecutable)").path
        }
        if let dev = devAppBinary { return dev.path }
        return "\(spec.installedAppPath)/Contents/MacOS/\(spec.appExecutable)"
    }

    private func launch(_ pot: Pot) throws {
        let proc = Process()
        if enclosingAppBundle == nil, let dev = devAppBinary {
            // Dev build: run the binary directly, detached from our stdio.
            proc.executableURL = dev
            proc.arguments = ["--pot", pot.name]
            proc.standardInput = FileHandle.nullDevice
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            return
        }
        // `open -n` starts a new process even when another pot of the same bundle is running
        // (plain `open -a` would only activate the existing one).
        var args = ["-n", "-g"]
        for key in ["UR_CONFIG_HOME", "UR_RUN_DIR"] {
            if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { args += ["--env", "\(key)=\(v)"] }
        }
        if let bundle = enclosingAppBundle { args.append(bundle.path) } else { args += ["-b", spec.bundleID] }
        args += ["--args", "--pot", pot.name]
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = args
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw UrError("could not launch pot '\(pot.name)'") }
    }

    private func waitUntilRunning(_ pot: Pot, timeout: TimeInterval = 8) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pot.isRunning { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw UrError("pot '\(pot.name)' did not start within \(Int(timeout))s")
    }

    private func installLaunchAgent(_ pot: Pot) throws {
        let plist: [String: Any] = [
            "Label": pot.launchAgentLabel,
            "ProgramArguments": [appExecutablePath, "--pot", pot.name],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: pot.launchAgentURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: pot.launchAgentURL)
        // Unload a previous copy first so re-running `--login` updates it instead of failing.
        // bootstrap then starts it (RunAtLoad); if the pot is already running, that second copy
        // finds the live socket and exits, which is harmless.
        _ = try? launchctl(["bootout", "gui/\(getuid())/\(pot.launchAgentLabel)"])
        guard try launchctl(["bootstrap", "gui/\(getuid())", pot.launchAgentURL.path]) == 0 else {
            throw UrError("launchctl bootstrap failed for \(pot.launchAgentURL.path)")
        }
    }

    @discardableResult
    private func launchctl(_ arguments: [String]) throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }
}

/// Alfred Script Filter output from a list reply. Each item may carry `id`, `name`/`title`,
/// `url`/`subtitle` and `address`; the address is the arg, so an Alfred "Open URL" action on
/// `{query}` routes straight back into the app.
public enum Alfred {
    public static func scriptFilter(_ data: JSONValue?) -> JSONValue {
        let rows = data?.arrayValue ?? data?["items"]?.arrayValue ?? []
        let items: [JSONValue] = rows.map { row in
            let title = row["title"]?.stringValue ?? row["name"]?.stringValue ?? row["id"]?.stringValue ?? ""
            let subtitle = row["subtitle"]?.stringValue ?? row["url"]?.stringValue ?? ""
            let arg = row["address"]?.stringValue ?? row["url"]?.stringValue ?? title
            var item: [String: JSONValue] = [
                "title": .string(title), "subtitle": .string(subtitle), "arg": .string(arg),
                "autocomplete": .string(title),
            ]
            if let id = row["id"]?.stringValue { item["uid"] = .string(id) }
            return .object(item)
        }
        return .object(["items": .array(items)])
    }
}
