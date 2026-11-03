# Release process

How to **ship** a new version (maintainers) and how to **pull** the latest build (users).

---

## Users: install and upgrade

### Homebrew (recommended)

```bash
brew tap o-o-o-o-o/ur-browse
brew install --cask ur-browse
```

Upgrade when a new version is out:

```bash
brew update && brew upgrade --cask ur-browse
```

The Cask (`Casks/ur-browse.rb`) is updated automatically at the end of each release CI run. It installs the `ur-browse` CLI and the legacy `gander` alias. The repo was renamed from `o-o-o-o-o/gander`; GitHub redirects the old URLs, and `cask_renames.json` maps the old `gander` cask name.

### Manual download

1. Open [GitHub Releases](https://github.com/o-o-o-o-o/ur-browse/releases).
2. Download `UrBrowse-vX.Y.Z.zip` for the version you want.
3. Unzip and drag `urBrowse.app` to `/Applications` (replace the old copy).

### Gatekeeper (unsigned app)

urBrowse is not notarized. After install or upgrade, macOS may block the first launch. Use **System Settings → Privacy & Security → Open Anyway**, or remove quarantine:

```bash
xattr -cr "/Applications/urBrowse.app"
```

---

## Maintainers: cut a release

### Before you start

1. **Pull** latest `main` and confirm you're up to date:

   ```bash
   git checkout main
   git pull origin main
   ```

2. **Commit** everything that should ship. `release.sh` refuses a dirty working tree.

3. **Test locally** (recommended):

   ```bash
   bash publish.sh
   ```

   Smoke-test the change with `open "urBrowse.app"` (repo root build) before tagging.

4. **Pick a version** (semver pre-1.0: `0.x.y`):

   | Change | Bump |
   |--------|------|
   | Bug fix, small behavior fix | patch (`0.1.8` → `0.1.9`) |
   | New user-visible feature | minor (`0.1.9` → `0.2.0`) |

   Check the latest tag:

   ```bash
   git tag --sort=-v:refname | head -1
   ```

### Ship it

```bash
bash scripts/release.sh 0.2.0
```

The script:

1. Runs `logic-test.sh`
2. Pushes `main` to `origin` (required so CI can push the Cask commit back)
3. Creates and pushes tag `v0.2.0`
4. Triggers [`.github/workflows/release.yml`](.github/workflows/release.yml)

### After tagging — verify CI, then pull

Always confirm both workflows succeed before calling the release done:

```bash
gh run list --repo o-o-o-o-o/ur-browse --limit 3
```

Expect:

- **CI** on `main` — success (from the release commit push)
- **Release** on `v0.2.0` — success

The Release workflow:

1. Builds `UrBrowse-v0.2.0.zip` on `macos-latest`
2. Creates a [GitHub Release](https://github.com/o-o-o-o-o/ur-browse/releases) with auto-generated notes
3. Updates `Casks/ur-browse.rb` (version + SHA256) and **pushes a new commit to `main`**

That Cask commit is made by CI on GitHub — your local `main` is now behind. **Pull it:**

```bash
git pull origin main
```

You should see `Casks/ur-browse.rb` updated to the version you just shipped. Skip this and the next local commit may conflict or re-do the Cask update.

Release page: `https://github.com/o-o-o-o-o/ur-browse/releases/tag/v0.2.0`

### If the Cask update fails

CI has failed before when `main` was not pushed before the tag (v0.1.5). `release.sh` now pushes `main` first to avoid that.

To fix a published release whose Cask did not update:

```bash
gh workflow run update-cask.yml --field version=v0.2.0
```

Or edit `Casks/ur-browse.rb` manually: set `version` and `sha256` from the release zip, commit, push.

---

## Quick reference

| Task | Command |
|------|---------|
| Local dev install | `bash publish.sh` |
| See latest tag | `git tag --sort=-v:refname \| head -1` |
| Cut release | `bash scripts/release.sh X.Y.Z` |
| Check CI | `gh run list --repo o-o-o-o-o/ur-browse --limit 3` |
| Sync Cask commit from CI | `git pull origin main` |
| User upgrade (Homebrew) | `brew update && brew upgrade --cask ur-browse` |

See also [CONTRIBUTING.md](CONTRIBUTING.md) (project layout), [BUILD_WORKFLOW.md](BUILD_WORKFLOW.md) (local build checklist), and [learnings.md](learnings.md) (release gotchas).
