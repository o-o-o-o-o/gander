import AppKit
import UrBrowseSpec
import UrKit

// Launch forms:
//   UrBrowse                     → the "default" pot
//   UrBrowse --pot work          → ~/.config/ur/browse/work/config.json
//   UrBrowse --config <path>     → explicit file; the pot is the file's "name" (smoke tests,
//                                  pre-rename LaunchAgents)
var potName: String? = nil
var configPath: String? = nil
var argv = CommandLine.arguments.dropFirst()[...]
while let arg = argv.first {
    argv = argv.dropFirst()
    switch arg {
    case "--pot":    potName = argv.first;    argv = argv.dropFirst()
    case "--config": configPath = argv.first; argv = argv.dropFirst()
    default: break  // ignore e.g. -NSDocumentRevisionsDebugMode from Xcode/LaunchServices
    }
}

func die(_ message: String) -> Never {
    fputs("ur-Browse: \(message)\n", stderr)
    exit(1)
}

/// Copies a pre-rename Gander config (~/.config/gander/<name>.json) into the pot folder once,
/// so existing setups keep working after the rename. The old file is left in place.
func migrateLegacyConfig(into pot: Pot) {
    let fm = FileManager.default
    let legacy = ("~/.config/gander/\(pot.name).json" as NSString).expandingTildeInPath
    guard !fm.fileExists(atPath: pot.configURL.path), fm.fileExists(atPath: legacy) else { return }
    do {
        try fm.createDirectory(at: pot.slipDirectory, withIntermediateDirectories: true)
        try fm.copyItem(atPath: legacy, toPath: pot.configURL.path)
        fputs("ur-Browse: migrated \(legacy) → \(pot.configURL.path)\n", stderr)
    } catch {
        fputs("ur-Browse: could not migrate \(legacy): \(error)\n", stderr)
    }
}

// Top-level names in main.swift are module-wide globals; the `launch` prefix keeps them from
// being confused with the `config` / `pot` properties used throughout the app.
var launchConfig: AppConfig
if let path = configPath {
    do { launchConfig = try AppConfig.load(from: path) }
    catch { die("cannot load config '\(path)': \(error)") }
    if let potName { launchConfig.name = potName }
} else {
    let name = potName ?? Pot.defaultName
    guard Pot.isValidName(name) else { die("invalid pot name '\(name)'") }
    let named = Pot(app: BrowseSpec.spec.app, name: name)
    migrateLegacyConfig(into: named)
    if FileManager.default.fileExists(atPath: named.configURL.path) {
        do { launchConfig = try AppConfig.load(from: named.configURL.path) }
        catch { die("cannot load config '\(named.configURL.path)': \(error)") }
    } else {
        launchConfig = AppConfig()
    }
    launchConfig.name = name  // the folder is the pot's identity, whatever "name" the file says
}
guard Pot.isValidName(launchConfig.name) else { die("invalid pot name '\(launchConfig.name)'") }

let launchPot = Pot(app: BrowseSpec.spec.app, name: launchConfig.name)
let launchDelegate = AppDelegate(config: launchConfig, pot: launchPot)
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.delegate = launchDelegate
NSApplication.shared.run()
