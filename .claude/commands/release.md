---
name: release
description: Full QwenWhisper release process — builds DMG, creates GitHub release with the standard banner, updates Homebrew tap. Use when the user says "выпустим релиз", "release", "новая версия", or wants to publish a new version.
---

# QwenWhisper Release Process

You are helping publish a new QwenWhisper release. Work through the steps below in order, confirming with the user at critical points.

## Step 1 — Get the version number

If the user hasn't specified a version, ask: "Какая версия? (например: 0.2.4)"

Set `VERSION` to the provided value (without the `v` prefix).

## Step 2 — Check git status

Run `git status` and `git log --oneline -5`.

- If there are uncommitted changes, tell the user and ask whether to commit them first or proceed anyway.
- Note the current HEAD for changelog generation.

## Step 3 — Get previous tag and recent commits

```bash
PREV_TAG=$(git describe --tags --abbrev=0 HEAD)
git log ${PREV_TAG}..HEAD --oneline
```

Use the commit list to draft the **What's Changed** bullet points. Clean up commit prefixes (`fix:`, `ui:`, `docs:`) into readable English lines.

## Step 4 — Build the release

```bash
./scripts/package_release.sh <VERSION>
```

This builds `dist/QwenWhisper-<VERSION>-macos-arm64.dmg` and `.zip`. Wait for it to complete (takes ~30–60s).

If it fails, show the error and stop.

## Step 5 — Compute SHA256

```bash
shasum -a 256 dist/QwenWhisper-<VERSION>-macos-arm64.dmg
```

Save this hash — it's needed for the Homebrew tap.

## Step 6 — Tag and push

```bash
git tag v<VERSION>
git push origin v<VERSION>
```

## Step 7 — Create GitHub release

Use this exact banner format for the release notes:

```
## Installation

Download `QwenWhisper-<VERSION>-macos-arm64.dmg` or `QwenWhisper-<VERSION>-macos-arm64.zip` below.

> ⚠️ **Note:** The app is not signed with an Apple Developer certificate. If macOS says the app is "damaged", open the DMG and double-click **Install QwenWhisper.command** — it handles everything automatically. Or run manually:
> ```
> xattr -cr /Applications/QwenWhisper.app
> ```

## What's Changed

- <generated bullet points from Step 3>

**Full Changelog:** https://github.com/hukopo/qwenwishper/compare/<PREV_TAG>...v<VERSION>
```

Run:

```bash
gh release create v<VERSION> \
  dist/QwenWhisper-<VERSION>-macos-arm64.dmg \
  dist/QwenWhisper-<VERSION>-macos-arm64.zip \
  --title "v<VERSION>" \
  --notes "<filled-in notes above>"
```

Show the user the release URL when done.

## Step 8 — Update Homebrew tap

Clone (or reuse) the tap:

```bash
# Clone fresh into /tmp to avoid stale state
rm -rf /tmp/homebrew-tap
git clone https://github.com/hukopo/homebrew-tap.git /tmp/homebrew-tap
```

Edit `/tmp/homebrew-tap/Casks/qwenwhisper.rb` — update exactly two lines:

```ruby
version "<VERSION>"
sha256 "<SHA256 from Step 5>"
```

Then commit and push:

```bash
cd /tmp/homebrew-tap
git add Casks/qwenwhisper.rb
git commit -m "chore: bump qwenwhisper to <VERSION>"
git push origin main
```

## Step 9 — Verify brew

```bash
brew update
brew info --cask hukopo/tap/qwenwhisper
```

Confirm the output shows the new version.

## Step 10 — Done

Report to the user:
- GitHub release URL
- brew install command: `brew install --cask hukopo/tap/qwenwhisper`
- Confirm everything succeeded
