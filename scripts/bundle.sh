#!/bin/bash
# Assemble "urBrowse.app" from already-built binaries. Shared by build.sh (local) and
# scripts/build-release.sh (CI) so the bundle layout is defined in exactly one place.
#
# Usage: bash scripts/bundle.sh <swift-bin-dir> <version>
set -euo pipefail
cd "$(dirname "$0")/.."

BIN_DIR="${1:?Usage: bundle.sh <swift-bin-dir> <version>}"
VERSION="${2:?Usage: bundle.sh <swift-bin-dir> <version>}"
APP_NAME="urBrowse"
APP_BUNDLE="${APP_NAME}.app"
WORK="$(mktemp -d /tmp/ur-browse-bundle.XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT

# ── App icon: goose on amber circle ──────────────────────────────────────────
ICONSET="${WORK}/UrBrowse.iconset"
mkdir "${ICONSET}"
ICONSET="${ICONSET}" swift - <<'SWIFT'
import AppKit

let iconset = ProcessInfo.processInfo.environment["ICONSET"]!
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let bg = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: s, height: s))
    NSColor(red: 0.95, green: 0.76, blue: 0.18, alpha: 1).setFill()
    bg.fill()
    // Goose emoji centred — 🪿 (U+1FABF, Unicode 15 / macOS 14+)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.68)]
    let str = NSAttributedString(string: "🪿", attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2))
    img.unlockFocus()
    if let tiff = img.tiffRepresentation,
       let rep  = NSBitmapImageRep(data: tiff),
       let png  = rep.representation(using: .png, properties: [:]) {
        let name = size <= 512 ? "icon_\(size)x\(size).png" : "icon_512x512@2x.png"
        try? png.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
    }
}
SWIFT
iconutil --convert icns "${ICONSET}" --output "${WORK}/AppIcon.icns"
echo "✓ icon generated"

# ── Menubar icon: remove white background from greg.png ─────────────────────
OUT="${WORK}/greg.png" swift - <<'SWIFT'
import AppKit
import CoreGraphics

let out = ProcessInfo.processInfo.environment["OUT"]!
guard let data = try? Data(contentsOf: URL(fileURLWithPath: "Resources/greg.png")),
      let provider = CGDataProvider(data: data as CFData),
      let cgSrc = CGImage(pngDataProviderSource: provider, decode: nil,
                          shouldInterpolate: true, intent: .defaultIntent) else { exit(1) }

let w = cgSrc.width, h = cgSrc.height
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: w, height: h))
let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
for i in 0..<(w * h) {
    let o = i * 4
    if pixels[o] > 230 && pixels[o+1] > 230 && pixels[o+2] > 230 {
        pixels[o] = 0; pixels[o+1] = 0; pixels[o+2] = 0; pixels[o+3] = 0
    }
}
let outImg = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
if let tiff = outImg.tiffRepresentation,
   let bmp  = NSBitmapImageRep(data: tiff),
   let png  = bmp.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out))
    print("✓ greg template processed (\(w)×\(h))")
}
SWIFT

# ── .app bundle ──────────────────────────────────────────────────────────────
rm -rf "${APP_BUNDLE}"
CONTENTS="${APP_BUNDLE}/Contents"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "${BIN_DIR}/UrBrowseApp" "${CONTENTS}/MacOS/UrBrowse"
# ur-browse-cli powers the `ur-browse` CLI (and the legacy `gander` alias). The Homebrew Cask
# symlinks both to Contents/MacOS/ur-browse-cli, so omitting it produces an app that looks
# fine but silently breaks every external trigger (CLI, BetterTouchTool, Alfred).
cp "${BIN_DIR}/ur-browse" "${CONTENTS}/MacOS/ur-browse-cli"
cp "${WORK}/AppIcon.icns" "${CONTENTS}/Resources/AppIcon.icns"
cp "${WORK}/greg.png"     "${CONTENTS}/Resources/greg.png"

# Both schemes are registered: ur-browse:// is canonical, gander:// keeps old bindings working.
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>UrBrowse</string>
    <key>CFBundleIdentifier</key><string>io.ur.browse</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>${APP_NAME}</string>
        <key>CFBundleURLSchemes</key><array><string>ur-browse</string><string>gander</string></array>
    </dict></array>
</dict></plist>
PLIST

# Re-seal after assembly: the linker's ad-hoc signature does not cover Info.plist/Resources,
# and Apple Silicon reports "damaged" for a quarantined app with an invalid signature.
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"
echo "✓ ${APP_BUNDLE} built at $(pwd)/${APP_BUNDLE}"
