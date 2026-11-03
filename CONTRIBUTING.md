# Contributing

## Local development

```bash
make build        # compile + build "Ur Browse.app" in project dir
make run          # build + open immediately for manual testing
make logic-test   # Swift unit tests (URL canonicalization, config, frame logic, site ids, slip, request parsing)
make smoke-test   # end-to-end: launches an isolated pot, exercises the CLI + socket IPC
make publish      # logic-test + build + smoke-test
make publish-open # same, then opens the app
```

`make build` and `make run` never touch `/Applications`. To replace the tap-installed version locally:

```bash
make install      # builds + copies to /Applications + registers URL scheme
```

## Releasing

See **[RELEASE.md](RELEASE.md)** for the full process (pull `main`, test, tag, verify CI, user upgrade via Homebrew or zip).

```bash
git pull origin main
bash publish.sh              # optional but recommended
bash scripts/release.sh 0.2.0
gh run list --repo o-o-o-o-o/ur-browse --limit 3
git pull origin main         # after CI: sync Casks/ur-browse.rb commit from release workflow
```

If the Cask ever gets out of sync:

```bash
gh workflow run update-cask.yml --field version=v0.2.0
```

## Project layout

```
Sources/
  UrKit/            shared Ur skeleton: pots, addressed requests, Unix-socket IPC, generic CLI
  UrBrowseSpec/     BrowseSpec: the one verb list + usage shared by app and CLI
  UrBrowse/         main app (NSPanel + WKWebView + menu bar), target UrBrowseApp
  ur-browse-cli/    CLI tool (one line: UrCLI(BrowseSpec.spec).run(); talks to the pot's socket)
Resources/
  greg.png         menubar icon source (white background removed at build time)
scripts/
  bundle.sh        assembles "Ur Browse.app"; shared by build.sh and build-release.sh
  build-release.sh CI build: compiles, bundles .app, zips UrBrowse-vX.Y.Z.zip
  release.sh       tag + push to trigger a release
Casks/
  ur-browse.rb     Homebrew Cask definition (auto-updated by release workflow)
.github/workflows/
  ci.yml           swift build + logic tests on PR / push to main
  release.yml      builds release artifact + creates GitHub Release + updates Cask
  update-cask.yml  manual Cask update (workflow_dispatch only)
```

Adding a verb: `BrowseSpec.verbs` (+ usage text), `BrowseCommand`, `AppDelegate.execute` — nothing else.
Files that `logic-test.sh` compiles together must wrap `import UrKit` in `#if canImport(UrKit)`.
Vocabulary (pot, throw, glaze, slip, kiln) is explained in [README.md](README.md#lexicon).
