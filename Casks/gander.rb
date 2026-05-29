# typed: false
# frozen_string_literal: true

cask "gander" do
  version "0.1.13"
  sha256 "94d4a6b82c49fabb70f71712fc21b3d9addafa8c2c3d58e9ea8bad6d75a44503"

  url "https://github.com/o-o-o-o-o/gander/releases/download/v#{version}/Gander-v#{version}.zip"
  name "Gander"
  desc "Floating sidebar browser that persists across all Aerospace spaces"
  homepage "https://github.com/o-o-o-o-o/gander"

  app "Gander.app"
  binary "#{appdir}/Gander.app/Contents/MacOS/gander-cli", target: "gander"

  caveats <<~EOS
    Gander is not signed with an Apple Developer certificate.
    On first launch macOS may block it. If that happens, run:
      xattr -dr com.apple.quarantine /Applications/Gander.app
    Or go to: System Settings → Privacy & Security → Open Anyway
  EOS
end
