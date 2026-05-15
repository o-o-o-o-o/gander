# typed: false
# frozen_string_literal: true

cask "gander" do
  version "0.1.3"
  sha256 "efab830aa5bb9654b56607dba664615fd3a00bd8afdd8776925f82812f06bf1e"

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
