---
description: Build, sign, notarize, and release OmniWM
argument-hint: [version]
---

# Release OmniWM

Release version: $ARGUMENTS

## Context

- Current version in Info.plist: !`grep -A1 CFBundleShortVersionString Info.plist | tail -1 | sed 's/.*<string>//' | sed 's/<.*//'`
- Last git tag: !`git tag --sort=-version:refname | head -1`
- Commits since last release: !`git log $(git tag --sort=-version:refname | head -1)..HEAD --oneline`

## Tasks

1. Update Info.plist with version $ARGUMENTS (also increment CFBundleVersion build number)
2. Run `./Scripts/package-app.sh release true` to build, sign, and notarize
3. Create release zip: `ditto -c -k --keepParent dist/OmniWM.app dist/OmniWM-v$ARGUMENTS.zip`
4. Get SHA256: `shasum -a 256 dist/OmniWM-v$ARGUMENTS.zip`
5. Commit version bump and push
6. Create GitHub release with `gh release create v$ARGUMENTS ./dist/OmniWM-v$ARGUMENTS.zip` including release notes based on commits
7. Update `/Users/barut/OmniWM/homebrew-tap/Casks/omniwm.rb` with new version and SHA256
8. Commit and push homebrew-tap changes

Verify the app shows correct version in the status bar menu (reads from CFBundleShortVersionString).
