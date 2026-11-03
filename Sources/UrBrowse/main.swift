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
    fputs("Ur Browse: \(message)\n", stderr)
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
        fputs("Ur Browse: migrated \(legacy) → \(pot.configURL.path)\n", stderr)
    } catch {
        fputs("Ur Browse: could not migrate \(legacy): \(error)\n", stderr)
    }
}

var config: AppConfig
if let path = configPath {
    do { config = try AppConfig.load(from: path) }
    catch { die("cannot load config '\(path)': \(error)") }
    if let potName { config.name = potName }
} else {
    let name = potName ?? Pot.defaultName
    guard Pot.isValidName(name) else { die("invalid pot name '\(name)'") }
    let pot = Pot(app: BrowseSpec.spec.app, name: name)
    migrateLegacyConfig(into: pot)
    if FileManager.default.fileExists(atPath: pot.configURL.path) {
        do { config = try AppConfig.load(from: pot.configURL.path) }
        catch { die("cannot load config '\(pot.configURL.path)': \(error)") }
    } else {
        config = AppConfig()
    }
    config.name = name  // the folder is the pot's identity, whatever "name" the file says
}
guard Pot.isValidName(config.name) else { die("invalid pot name '\(config.name)'") }

let pot = Pot(app: BrowseSpec.spec.app, name: config.name)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(config: config, pot: pot)
app.delegate = delegate
app.run()
