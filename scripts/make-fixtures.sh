#!/bin/bash
# Builds a throwaway ~/Code-like folder for trying Grove's cleanup actions safely.
# Usage: scripts/make-fixtures.sh <dir>   then: open build/Grove.app --args -rootPath <dir>/code
set -euo pipefail
ROOT="${1:?usage: make-fixtures.sh <dir>}"
rm -rf "$ROOT"
mkdir -p "$ROOT/remotes" "$ROOT/code" "$ROOT/elsewhere"
ROOT="$(cd "$ROOT" && pwd -P)"
CODE="$ROOT/code"

# Keep fixtures independent of the machine's git setup (signing, hooks, templates).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Fern Example" GIT_AUTHOR_EMAIL="fern@example.com"
export GIT_COMMITTER_NAME="Fern Example" GIT_COMMITTER_EMAIL="fern@example.com"

days_ago() { date -v-"$1"d "+%Y-%m-%dT12:00:00"; }
stamp() { date -v-"$1"d "+%Y%m%d1200"; }

commit() { # repo, days ago, message
  local repo=$1 days=$2 msg=$3
  echo "$msg $RANDOM" >> "$repo/notes.txt"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE=$(days_ago "$days") GIT_COMMITTER_DATE=$(days_ago "$days") git -C "$repo" commit -qm "$msg"
}

age() { # make a checkout look untouched for N days
  local gitdir; gitdir=$(git -C "$1" rev-parse --path-format=absolute --git-dir)
  touch -t "$(stamp "$2")" "$gitdir/HEAD" "$gitdir/logs/HEAD" 2>/dev/null || true
}

new_repo() { # name, days ago, [with-remote]
  local name=$1 days=$2
  git init -q -b main "$CODE/$name"
  commit "$CODE/$name" "$((days + 30))" "Initial commit"
  commit "$CODE/$name" "$days" "Tidy up"
  if [ "${3:-}" = remote ]; then
    git init -q --bare -b main "$ROOT/remotes/$name.git"
    git -C "$CODE/$name" remote add origin "$ROOT/remotes/$name.git"
    git -C "$CODE/$name" push -qu origin main
    git -C "$CODE/$name" remote set-head origin main
  fi
}

# An active project with a pile of worktrees in every state.
new_repo nebula-api 1 remote
R="$CODE/nebula-api"
git -C "$R" worktree add -q -b feature/login "$CODE/nebula-api-login"
commit "$CODE/nebula-api-login" 20 "Add login"
git -C "$R" merge -q --no-edit feature/login
git -C "$R" push -q origin main
age "$CODE/nebula-api-login" 20

git -C "$R" worktree add -q -b wip/search "$CODE/nebula-api-search"
commit "$CODE/nebula-api-search" 0 "Search, half done"
echo "draft" > "$CODE/nebula-api-search/draft.md"

git -C "$R" worktree add -q -b fix/pagination "$CODE/nebula-api-pagination"
commit "$CODE/nebula-api-pagination" 12 "Fix pagination"
git -C "$CODE/nebula-api-pagination" push -qu origin fix/pagination
git -C "$R" push -q origin --delete fix/pagination
git -C "$R" fetch -q --prune
age "$CODE/nebula-api-pagination" 12

mkdir -p "$R/.claude/worktrees"
git -C "$R" worktree add -q -b review/pr-42 "$R/.claude/worktrees/review-pr-42"
commit "$R/.claude/worktrees/review-pr-42" 30 "Review notes"
git -C "$R/.claude/worktrees/review-pr-42" push -qu origin review/pr-42
age "$R/.claude/worktrees/review-pr-42" 30

git -C "$R" worktree add -q -b spike/cache "$ROOT/elsewhere/nebula-cache-spike"
age "$ROOT/elsewhere/nebula-cache-spike" 40

git -C "$R" worktree add -q -b old/experiment "$CODE/nebula-api-experiment"
rm -rf "$CODE/nebula-api-experiment"

for b in chore/deps docs/readme fix/typo; do
  git -C "$R" branch "$b"
  git -C "$R" push -q origin "$b"
  git -C "$R" push -q origin --delete "$b"
done
git -C "$R" branch --set-upstream-to=origin/main chore/deps >/dev/null
git -C "$R" fetch -q --prune
age "$R" 1

# Dormant, everything pushed.
new_repo pixel-garden 220 remote; age "$CODE/pixel-garden" 220
new_repo retro-weather 400 remote; age "$CODE/retro-weather" 400

# Dormant but has unpushed work.
new_repo ledger-cli 150 remote
commit "$CODE/ledger-cli" 140 "Local-only change"
age "$CODE/ledger-cli" 140

# Idle, local only.
new_repo recipe-notes 45; age "$CODE/recipe-notes" 45

# Active with uncommitted changes.
new_repo moss-site 2 remote
echo "edit" >> "$CODE/moss-site/notes.txt"

# A group folder holding repositories.
mkdir -p "$CODE/clients"
git init -q -b main "$CODE/clients/acme-portal"; commit "$CODE/clients/acme-portal" 70 "Portal"; age "$CODE/clients/acme-portal" 70
git init -q -b main "$CODE/clients/birch-dashboard"; commit "$CODE/clients/birch-dashboard" 5 "Dashboard"

# Loose folders.
mkdir -p "$CODE/scratch" "$CODE/old-screenshots"
echo hi > "$CODE/scratch/todo.txt"
dd if=/dev/zero of="$CODE/old-screenshots/blob.bin" bs=1m count=2 2>/dev/null
touch -t "$(stamp 300)" "$CODE/old-screenshots/blob.bin" "$CODE/old-screenshots"

echo "$CODE"
