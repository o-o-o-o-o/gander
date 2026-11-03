# typed: false
# frozen_string_literal: true

cask "ur-browse" do
  version "0.5.0"
  sha256 "f263a165b8fa679709c312ae44614e6056326c970c03cf6420c3850139538b4b"

  url "https://github.com/o-o-o-o-o/ur-browse/releases/download/v#{version}/UrBrowse-v#{version}.zip"
  name "urBrowse"
  desc "Floating sidebar browser with many independent pots (instances)"
  homepage "https://github.com/o-o-o-o-o/ur-browse"

  app "urBrowse.app"
  binary "#{appdir}/urBrowse.app/Contents/MacOS/ur-browse-cli", target: "ur-browse"
  # Legacy alias: keeps existing `gander …` BetterTouchTool / Alfred / shell bindings working.
  binary "#{appdir}/urBrowse.app/Contents/MacOS/ur-browse-cli", target: "gander"

  # Ad-hoc signed, not notarized: Apple Silicon Gatekeeper reports a quarantined copy as "damaged".
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/urBrowse.app"]
  end

  caveats <<~EOS
    urBrowse is not signed with an Apple Developer certificate.
    The install removes the quarantine flag so that macOS does not report it as "damaged".
    If macOS still blocks it, run:
      xattr -dr com.apple.quarantine "/Applications/urBrowse.app"
  EOS
end
