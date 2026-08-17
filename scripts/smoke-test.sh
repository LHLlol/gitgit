#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pushdock-smoke.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

REMOTE="$TEST_ROOT/remote.git"
LOCAL="$TEST_ROOT/中文 Projects/My Repo"
mkdir -p "$LOCAL"

git init --bare "$REMOTE" >/dev/null
git -C "$LOCAL" init -b main >/dev/null
git -C "$LOCAL" config user.name "PushDock Smoke"
git -C "$LOCAL" config user.email "pushdock-smoke@example.com"
printf 'initial\n' > "$LOCAL/README.md"
git -C "$LOCAL" add -A
git -C "$LOCAL" commit -m "Initial" >/dev/null
git -C "$LOCAL" remote add origin "$REMOTE"
git -C "$LOCAL" push -u origin main >/dev/null
printf 'modified through a path with spaces and Chinese characters\n' > "$LOCAL/README.md"
mkdir -p "$LOCAL/src/components"

SMOKE_BINARY="$TEST_ROOT/GitCoreSmoke"
swiftc -swift-version 5 -O -parse-as-library \
  "$PROJECT_ROOT/Tests/GitCoreSmoke.swift" \
  "$PROJECT_ROOT/PushDock/Models/GitChange.swift" \
  "$PROJECT_ROOT/PushDock/Models/GitOperation.swift" \
  "$PROJECT_ROOT/PushDock/Models/GitStatus.swift" \
  "$PROJECT_ROOT/PushDock/Models/Repository.swift" \
  "$PROJECT_ROOT/PushDock/Services/ProcessRunner.swift" \
  "$PROJECT_ROOT/PushDock/Services/GitService.swift" \
  "$PROJECT_ROOT/PushDock/Utilities/FileSizeChecker.swift" \
  "$PROJECT_ROOT/PushDock/Utilities/GitErrorParser.swift" \
  "$PROJECT_ROOT/PushDock/Utilities/RemoteURLParser.swift" \
  -o "$SMOKE_BINARY"

"$SMOKE_BINARY" "$LOCAL/src/components"
