# Gander Build Workflow

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
4. Runs `bash smoke-test.sh` against an isolated temporary instance and checks the installed app's `gander://show`, `gander://toggle`, and `gander://hide` handlers.
5. Registers the `gander://` URL scheme.
6. Reinstalls `/Applications/Gander.app`.

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
open /Applications/Gander.app
```

Or via `make`:

```bash
make publish
make publish-open
```

## What `build.sh` publishes

- Builds `GanderApp` in release mode.
- Regenerates the app icon.
- Processes `Resources/greg.png` into the bundled menubar template image.
- Refreshes `Gander.app` in the repo.
- Copies the app to `/Applications/Gander.app`.
- Rebuilds the `gander` CLI binary.
- Installs the CLI to `/usr/local/bin/gander` only when that directory is writable.

## Verification checklist

1. Confirm the build completes without compiler errors.
2. Confirm smoke tests pass.
3. Launch `/Applications/Gander.app`.
4. Confirm the menubar icon size looks correct.
5. Confirm the installed app still responds to `gander://show`, `gander://toggle`, and `gander://hide`.
6. If you changed config, window frame, or site routing, test one configured URL and one ad hoc URL.

## Publishing rule of thumb

After any user-visible change, prefer `bash publish.sh --open` instead of running `swift build` alone. `swift build` only validates compilation; it does not refresh the installed app in `/Applications`.