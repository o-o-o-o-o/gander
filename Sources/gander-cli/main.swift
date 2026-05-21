// gander — CLI control for Gander
//
// Usage:  gander [instance] <command> [url] [--x n --y n --width n --height n]
// Commands: toggle  show  hide  sites  next  prev  open <url>  frame
//
// Examples:
//   gander toggle
//   gander sites
//   gander open https://example.com
//   gander show --width 480 --height 900
//   gander frame laptop
//   gander frame --width 30% --height 100%
//   gander work toggle

import Foundation

struct FrameOptions {
    var preset: String?
    var x: String?
    var y: String?
    var width: String?
    var height: String?

    var isEmpty: Bool {
        preset == nil && x == nil && y == nil && width == nil && height == nil
    }

    func asUserInfo() -> [String: Any] {
        var userInfo: [String: Any] = [:]
        if let preset { userInfo["preset"] = preset }
        if let x { userInfo["x"] = x }
        if let y { userInfo["y"] = y }
        if let width { userInfo["width"] = width }
        if let height { userInfo["height"] = height }
        return userInfo
    }
}

func usage() -> String {
    """
    Usage:
      gander [instance] toggle
      gander [instance] show [--x v --y v --width v --height v]
      gander [instance] hide
      gander [instance] sites
      gander [instance] next
      gander [instance] prev
      gander [instance] open <url> [--shortcut 1-9] [--x v --y v --width v --height v]
      gander [instance] frame <preset> [--x v --y v --width v --height v]
      gander [instance] frame --x v --y v --width v --height v
      gander [instance] menubar

    Dimension values: points (420), percent (30%), or full/max/100% for height/width.
    Position: points, percent, or right/left/bottom/top for --x/--y.
    """
}

func parseFrameValue(name: String, rawValue: String) -> String {
    let v = rawValue.trimmingCharacters(in: .whitespaces)
    if v.isEmpty {
        fputs("gander: '\(name)' requires a value\n\(usage())\n", stderr)
        exit(1)
    }
    return v
}

func parseURLAndFrame(_ args: [String], requiresURL: Bool) -> (String?, FrameOptions) {
    var url: String? = nil
    var frame = FrameOptions()
    var index = 0

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--x", "--y", "--width", "--height":
            index += 1
            guard index < args.count else {
                fputs("gander: '\(arg)' requires a value\n\(usage())\n", stderr)
                exit(1)
            }
            let value = parseFrameValue(name: arg, rawValue: args[index])
            switch arg {
            case "--x": frame.x = value
            case "--y": frame.y = value
            case "--width": frame.width = value
            case "--height": frame.height = value
            default: break
            }
        default:
            if arg.hasPrefix("--") {
                fputs("gander: unknown option '\(arg)'\n\(usage())\n", stderr)
                exit(1)
            }
            if requiresURL && url == nil {
                url = arg
            } else if frame.preset == nil && !requiresURL {
                frame.preset = arg
            } else {
                fputs("gander: unexpected argument '\(arg)'\n\(usage())\n", stderr)
                exit(1)
            }
        }
        index += 1
    }

    if requiresURL && url == nil {
        fputs("gander: 'open' requires a URL\n\(usage())\n", stderr)
        exit(1)
    }

    return (url, frame)
}

let knownCommands = ["toggle", "show", "hide", "sites", "next", "prev", "open", "frame", "menubar"]
var args = Array(CommandLine.arguments.dropFirst())

let instanceName: String
let command: String

if args.isEmpty {
    instanceName = "default"; command = "toggle"
} else if knownCommands.contains(args[0]) {
    instanceName = "default"; command = args.removeFirst()
} else {
    instanceName = args.removeFirst()
    command = args.isEmpty ? "toggle" : args.removeFirst()
}

let prefix = "com.gander.\(instanceName)"
let nc = DistributedNotificationCenter.default()

switch command {
case "toggle":
    nc.postNotificationName(.init("\(prefix).toggle"), object: nil, deliverImmediately: true)
case "show":
    let (_, frame) = parseURLAndFrame(args, requiresURL: false)
    nc.postNotificationName(.init("\(prefix).show"), object: nil,
                            userInfo: frame.asUserInfo(), deliverImmediately: true)
case "hide":
    nc.postNotificationName(.init("\(prefix).hide"), object: nil, deliverImmediately: true)
case "sites":
    nc.postNotificationName(.init("\(prefix).sites"), object: nil, deliverImmediately: true)
case "next":
    nc.postNotificationName(.init("\(prefix).next"), object: nil, deliverImmediately: true)
case "prev":
    nc.postNotificationName(.init("\(prefix).prev"), object: nil, deliverImmediately: true)
case "open":
    var remainingArgs: [String] = []
    var shortcut: Int? = nil
    var i = 0
    while i < args.count {
        if args[i] == "--shortcut" {
            i += 1
            guard i < args.count else {
                fputs("gander: '--shortcut' requires a value (1–9)\n\(usage())\n", stderr)
                exit(1)
            }
            guard let n = Int(args[i]), (1...9).contains(n) else {
                fputs("gander: '--shortcut' requires a number between 1 and 9\n\(usage())\n", stderr)
                exit(1)
            }
            shortcut = n
        } else {
            remainingArgs.append(args[i])
        }
        i += 1
    }
    let (url, frame) = parseURLAndFrame(remainingArgs, requiresURL: true)
    var userInfo = frame.asUserInfo()
    userInfo["url"] = url!
    if let n = shortcut { userInfo["shortcut"] = n }
    nc.postNotificationName(.init("\(prefix).open"), object: nil,
                            userInfo: userInfo, deliverImmediately: true)
case "frame":
    let (_, frame) = parseURLAndFrame(args, requiresURL: false)
    guard !frame.isEmpty else {
        fputs("gander: 'frame' requires a preset name or at least one of --x, --y, --width, --height\n\(usage())\n", stderr)
        exit(1)
    }
    nc.postNotificationName(.init("\(prefix).frame"), object: nil,
                            userInfo: frame.asUserInfo(), deliverImmediately: true)
case "menubar":
    nc.postNotificationName(.init("\(prefix).menubar"), object: nil, deliverImmediately: true)
default:
    fputs("gander: unknown command '\(command)'\n\(usage())\n", stderr)
    exit(1)
}

Thread.sleep(forTimeInterval: 0.15)
