# typed: false
# frozen_string_literal: true

cask "gander" do
  version "0.1.10"
  sha256 "dc107e386f50777ef3568b643282e3d7ec994c7c606a0b6bdfdb8c45ea2a93ef"

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
