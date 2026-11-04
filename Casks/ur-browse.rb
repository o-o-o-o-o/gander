# typed: false
# frozen_string_literal: true

cask "ur-browse" do
  version "0.6.2"
  sha256 "c0499643ff6495c3c0b8e8e39547f69bd61ac0d36b02f96be459d4ed2176bd8b"

  url "https://github.com/o-o-o-o-o/ur-browse/releases/download/v#{version}/UrBrowse-v#{version}.zip"
  name "ur-Browse"
  desc "Floating sidebar browser with many independent pots (instances)"
  homepage "https://github.com/o-o-o-o-o/ur-browse"

  app "ur-Browse.app"
  binary "#{appdir}/ur-Browse.app/Contents/MacOS/ur-browse-cli", target: "ur-browse"
  # Legacy alias: keeps existing `gander …` BetterTouchTool / Alfred / shell bindings working.
  binary "#{appdir}/ur-Browse.app/Contents/MacOS/ur-browse-cli", target: "gander"

  # Ad-hoc signed, not notarized: Apple Silicon Gatekeeper reports a quarantined copy as "damaged".
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/ur-Browse.app"]
  end

  caveats <<~EOS
    ur-Browse is not signed with an Apple Developer certificate.
    The install removes the quarantine flag so that macOS does not report it as "damaged".
    If macOS still blocks it, run:
      xattr -dr com.apple.quarantine "/Applications/ur-Browse.app"
  EOS
end
