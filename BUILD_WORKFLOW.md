# Ur Browse Build Workflow

Use this whenever you change app code, assets, or packaging.

## Default command

```bash
bash publish.sh
make publish
```

What it does:

1. Runs `swift build` for a fast compile check.
2. Runs `bash logic-test.sh` for source-level logic checks that work with Command Line Tools.
3. Runs `bash build.sh` to produce the release app bundle.
4. Runs `bash smoke-test.sh` against an isolated temporary pot (temp config, temp socket, ephemeral website data) through the `ur-browse` CLI, and checks the installed app's `ur-browse://show`, `ur-browse://toggle`, and `ur-browse://hide` handlers.
5. Registers the `ur-browse://` (and legacy `gander://`) URL schemes.
6. Builds `./Ur Browse.app` in the repo root (does not touch `/Applications`).

Optional flags:

```bash
bash publish.sh --open
bash publish.sh --skip-tests
bash publish.sh --skip-smoke
make publish-open
```

## Manual steps behind the wrapper

```bash
swift build
bash logic-test.sh
bash build.sh
bash smoke-test.sh
open "Ur Browse.app"
```

Or via `make`:

```bash
make publish
make publish-open
```

## What `build.sh` publishes

- Builds `UrBrowseApp` and `ur-browse` (the CLI) in release mode.
- Hands the binaries to `scripts/bundle.sh`, which (shared with the CI release build) regenerates the
  app icon, processes `Resources/greg.png` into the bundled menubar template image, and writes
  `Ur Browse.app` in the repo root.

The CLI is **not** installed to `/usr/local/bin` by `build.sh`. In local dev use
`.build/release/ur-browse` directly. For users, the CLI reaches PATH via the Homebrew Cask's
`binary` stanzas (`ur-browse-cli` inside the bundle, symlinked as `ur-browse` and as the legacy
`gander`).

## Verification checklist

1. Confirm the build completes without compiler errors.
2. Confirm smoke tests pass.
3. Launch `Ur Browse.app` from the repo root.
4. Confirm the menubar icon size looks correct.
5. Confirm the installed app still responds to `ur-browse://show`, `ur-browse://toggle`, and `ur-browse://hide` (and that `ur-browse pots` lists your pots).
6. If you changed config, window frame, or site routing, test one configured site (`ur-browse site <id>`) and one ad hoc URL.

## Publishing rule of thumb

After any user-visible change, prefer `bash publish.sh --open` instead of running `swift build` alone. `swift build` only validates compilation; it does not refresh the installed app in `/Applications`.