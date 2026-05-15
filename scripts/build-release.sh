#!/bin/bash
set -e
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: build-release.sh <version>}"

swift build -c release --product GanderApp
swift build -c release --product gander

# ── App icon ─────────────────────────────────────────────────────────────────
ICONSET=/tmp/Gander.iconset
rm -rf "$ICONSET" && mkdir "$ICONSET"

swift - <<'SWIFT'
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = "/tmp/Gander.iconset"

for size in sizes {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let bg = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: s, height: s))
    NSColor(red: 0.95, green: 0.76, blue: 0.18, alpha: 1).setFill()
    bg.fill()

    let fontSize = s * 0.68
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize)
    ]
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

iconutil --convert icns "$ICONSET" --output /tmp/Gander.icns
echo "✓ icon generated"

# ── Menubar icon ─────────────────────────────────────────────────────────────
swift - <<'SWIFT'
import AppKit
import CoreGraphics

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
    try? png.write(to: URL(fileURLWithPath: "/tmp/greg_template.png"))
    print("✓ greg template processed (\(w)×\(h))")
}
SWIFT

# ── .app bundle ───────────────────────────────────────────────────────────────
BIN_DIR=$(swift build -c release --show-bin-path)
APP_BIN="${BIN_DIR}/GanderApp"
CLI_BIN="${BIN_DIR}/gander"

# Diagnostics: print sizes so CI logs show what was actually built
echo "  GanderApp: $(wc -c < "$APP_BIN" | tr -d ' ') bytes at $APP_BIN"
echo "  gander:    $(wc -c < "$CLI_BIN" | tr -d ' ') bytes at $CLI_BIN"

# Sanity check: app binary must contain AppDelegate (only in the app target)
if ! nm "$APP_BIN" 2>/dev/null | grep -q "AppDelegate"; then
    echo "❌ $APP_BIN does not look like the app binary (no AppDelegate symbol)" >&2
    echo "   nm output (first 10 lines):" >&2
    nm "$APP_BIN" 2>/dev/null | head -10 >&2
    exit 1
fi
echo "  ✓ app binary verified (AppDelegate present)"

rm -rf Gander.app
APP="Gander.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources"

cp "$APP_BIN" "$APP/MacOS/Gander"
cp "$CLI_BIN" "$APP/MacOS/gander"
cp /tmp/Gander.icns          "$APP/Resources/AppIcon.icns"
cp /tmp/greg_template.png    "$APP/Resources/greg.png"

cat > "$APP/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Gander</string>
    <key>CFBundleIdentifier</key><string>io.gander.app</string>
    <key>CFBundleName</key><string>Gander</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>Gander</string>
        <key>CFBundleURLSchemes</key><array><string>gander</string></array>
    </dict></array>
</dict></plist>
PLIST

echo "✓ Gander.app built"

# ── Zip ───────────────────────────────────────────────────────────────────────
ZIP="Gander-v${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent Gander.app "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "✓ ${ZIP}"
echo "  SHA256: ${SHA}"
