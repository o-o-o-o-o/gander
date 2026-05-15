# typed: false
# frozen_string_literal: true

cask "gander" do
  version "0.1.1"
  sha256 "c1b3c27678a3d63741af5cb1c9dacde642bdf81be7708c8cf56ba657002ae4e5"

  url "https://github.com/o-o-o-o-o/gander/releases/download/v#{version}/Gander-v#{version}.zip"
  name "Gander"
  desc "Floating sidebar browser that persists across all Aerospace spaces"
  homepage "https://github.com/o-o-o-o-o/gander"

  app "Gander.app"
  binary "#{appdir}/Gander.app/Contents/MacOS/gander"

  caveats <<~EOS
    Gander is not signed with an Apple Developer certificate.
    On first launch macOS may block it. If that happens, run:
      xattr -dr com.apple.quarantine /Applications/Gander.app

    Alternatively, install without quarantine in the first place:
      brew install --no-quarantine --cask gander

    Or go to: System Settings → Privacy & Security → Open Anyway
  EOS
end
