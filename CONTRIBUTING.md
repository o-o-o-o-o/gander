# Contributing

## Local development

```bash
make build        # compile + build Gander.app in project dir
make run          # build + open immediately for manual testing
make logic-test   # Swift unit tests (URL canonicalization, config, frame logic)
make smoke-test   # end-to-end: launches isolated instance, exercises CLI + IPC
make publish      # logic-test + build + smoke-test
make publish-open # same, then opens the app
```

`make build` and `make run` never touch `/Applications`. To replace the tap-installed version locally:

```bash
make install      # builds + copies to /Applications + registers URL scheme
```

## Releasing

```bash
bash scripts/release.sh 0.2.0
```

That's it. The script guards against a dirty working tree and duplicate tags, then pushes the tag. GitHub Actions takes over:

1. **`release.yml`** — builds `Gander-v0.2.0.zip` on `macos-latest`, attaches it to a GitHub Release, and commits the updated SHA256 into `Casks/gander.rb`
2. Users running `brew upgrade gander` pick up the new version automatically

If the Cask ever gets out of sync, re-run the update manually:

```
gh workflow run update-cask.yml --field version=v0.2.0
```

## Project layout

```
Sources/
  Gander/          main app (NSPanel + WKWebView + menu bar)
  gander-cli/      CLI tool (posts NSDistributedNotifications to the app)
Resources/
  greg.png         menubar icon source (white background removed at build time)
scripts/
  build-release.sh CI build: compiles, bundles .app, zips for distribution
  release.sh       tag + push to trigger a release
Casks/
  gander.rb        Homebrew Cask definition (auto-updated by release workflow)
.github/workflows/
  ci.yml           swift build + logic tests on PR / push to main
  release.yml      builds release artifact + creates GitHub Release + updates Cask
  update-cask.yml  manual Cask update (workflow_dispatch only)
```
