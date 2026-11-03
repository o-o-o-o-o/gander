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
        fputs("Ur Browse: cannot load config '\(path)': \(error)\n", stderr)
        exit(1)
    }
} else {
    // ~/.config/ur/browse/default/config.json, then the pre-rename ~/.config/gander/default.json
    let paths = ["~/.config/ur/browse/default/config.json", "~/.config/gander/default.json"]
    config = paths.lazy.compactMap { try? AppConfig.load(from: $0) }.first ?? AppConfig()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(config: config)
app.delegate = delegate
app.run()
