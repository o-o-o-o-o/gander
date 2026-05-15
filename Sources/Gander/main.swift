import AppKit

// Parse --config <path>
var remaining = CommandLine.arguments.dropFirst()[...]
var configPath: String? = nil
while let arg = remaining.first {
    remaining = remaining.dropFirst()
    if arg == "--config", let next = remaining.first {
        configPath = next
        break
    }
}

let config: AppConfig
if let path = configPath {
    do {
        config = try AppConfig.load(from: path)
    } catch {
        fputs("Gander: cannot load config '\(path)': \(error)\n", stderr)
        exit(1)
    }
} else {
    // Fall back to ~/.config/gander/default.json if it exists
    let fallback = ("~/.config/gander/default.json" as NSString).expandingTildeInPath
    config = (try? AppConfig.load(from: fallback)) ?? AppConfig()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(config: config)
app.delegate = delegate
app.run()
