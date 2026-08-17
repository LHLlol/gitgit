# PushDock

PushDock is a native SwiftUI macOS utility for syncing local GitHub projects without repeatedly typing Git commands in Terminal.

## Requirements

- macOS 13 or later
- Swift 5.9+ / Xcode 15+ for normal app development
- Git available in the local environment (`/usr/bin/git` is preferred)

The current repository can also be compiled with the Swift toolchain installed through Command Line Tools:

```bash
swift build
```

To create a directly runnable application bundle:

```bash
./scripts/build-app.sh
open PushDock.app
```

The build script is useful on a machine without the full Xcode app. With Xcode installed, `Package.swift` can be opened directly in Xcode and the executable target can be run or archived normally.

## Architecture

The app is split into:

- `Models/` — repository, Git status, changes, activity, settings, and operation state.
- `Services/ProcessRunner.swift` — asynchronous `Process` execution with separate stdout/stderr streaming.
- `Services/GitService.swift` — all Git commands, repository discovery, status parsing, safe sync state machine, remote operations, and conflict detection.
- `Services/BookmarkStore.swift` — security-scoped bookmark persistence for recently used repositories.
- `ViewModels/AppViewModel.swift` — main-actor MVVM state and UI commands.
- `Views/` — native SwiftUI sidebar, dashboard, empty state, settings, activity, and execution log surfaces.
- `Utilities/` — human-readable Git errors, remote redaction/display parsing, and large-file checks.

## How it works

1. Drop a folder from Finder or choose it with the native folder picker.
2. PushDock asks Git for the real repository root with `rev-parse`, so dropping a nested folder works.
3. The dashboard reads real branch, remote, user, ahead/behind, working-tree, and conflict state.
4. Sync stages with `git add -A`, creates a commit only when staged changes exist, fetches, rebases when needed, and pushes the current branch.
5. A push rejection is retried once with fetch/rebase. Rebase conflicts stop the workflow immediately; PushDock never resolves them or pushes through them.

Git arguments are always passed as an array to `Process`. Commit messages, paths with spaces/Chinese characters, and remote URLs are not interpolated into shell commands.

## Safety

PushDock never runs:

- `git reset --hard`
- `git clean -fd`
- `git push --force` / `git push -f`
- automatic `.git` deletion

If a local commit succeeds but the push fails, the local commit is kept and the UI offers a retry path. Authentication is delegated to the existing Git SSH/HTTPS/Keychain setup; PushDock does not store passwords, SSH keys, or tokens.

## Privacy

PushDock does not upload project files to its own server. All Git operations run locally using the user's existing Git configuration. There is no OAuth, account, analytics, tracking, crash upload, or telemetry.

Repository bookmarks, settings, and PushDock activity history are stored locally under `~/Library/Application Support/PushDock/`.

## Known limitations

The first release intentionally keeps the scope focused on safe local sync. Single-file staging, branch switching, clone flow, GitHub API integration, Git LFS management, Finder extensions, menu-bar quick actions, and notifications are not included yet.

The current local build uses a Swift Package and a small bundle script instead of a checked-in `.xcodeproj` because this environment does not have the full Xcode application installed. The package target is ready to open in Xcode.

## Gitgit 网页版

The browser implementation lives in [`docs/`](docs/). It is a dependency-free GitHub Pages site with the Gitgit workflow and visual language. Deploy the `/docs` folder through GitHub Pages. For real local Git operations, run the optional companion with `node docs/bridge/server.mjs`; a pure static webpage cannot execute local Git or access macOS SSH credentials on its own.
