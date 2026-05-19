# typed: false
# frozen_string_literal: true

cask "gander" do
  version "0.1.11"
  sha256 "4135afc73f0e961f4f1a7a815e2b487767fdee77c05cf8def0e6193f6ac70017"

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
