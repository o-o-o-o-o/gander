# typed: false
# frozen_string_literal: true

cask "gander" do
  version "0.1.2"
  sha256 "3728ae23685296f8e31f3c80b471cd8d14ef3fa080996e8b262ffd2544dbe4ec"

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
