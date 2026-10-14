# typed: false
# frozen_string_literal: true

cask "gander" do
  version "0.3.1"
  sha256 "7f65ce4b2c89afe1d7bc81c6805ffbed9ea4d47fd5471fe36e997dbfd31f4f6e"

  url "https://github.com/o-o-o-o-o/gander/releases/download/v#{version}/Gander-v#{version}.zip"
  name "Gander"
  desc "Floating sidebar browser that persists across all Aerospace spaces"
  homepage "https://github.com/o-o-o-o-o/gander"

  app "Gander.app"
  binary "#{appdir}/Gander.app/Contents/MacOS/gander-cli", target: "gander"

  # Ad-hoc signed, not notarized: Apple Silicon Gatekeeper reports a quarantined copy as "damaged".
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Gander.app"]
  end

  caveats <<~EOS
    Gander is not signed with an Apple Developer certificate.
    The install removes the quarantine flag so that macOS does not report it as "damaged".
    If macOS still blocks it, run:
      xattr -dr com.apple.quarantine /Applications/Gander.app
  EOS
end
