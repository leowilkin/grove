#!/bin/bash
# A believable, entirely fictional ~/Code for marketing screenshots.
# Usage: scripts/make-showcase.sh <fakehome>   -> builds <fakehome>/Code
# Every name here is made up; never point the screenshots at a real code folder.
set -euo pipefail
HOMEDIR="${1:?usage}"
rm -rf "$HOMEDIR"; mkdir -p "$HOMEDIR/Code" "$HOMEDIR/remotes" "$HOMEDIR/.codex/worktrees" "$HOMEDIR/blobs"
HOMEDIR="$(cd "$HOMEDIR" && pwd -P)"; CODE="$HOMEDIR/Code"; REM="$HOMEDIR/remotes"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$HOMEDIR"
export GIT_AUTHOR_NAME="Fern Example" GIT_AUTHOR_EMAIL="fern@example.com"
export GIT_COMMITTER_NAME="Fern Example" GIT_COMMITTER_EMAIL="fern@example.com"

# Size ballast: one real blob, cloned (APFS) wherever a folder should look heavy. du counts each clone in full.
mkfile 64m "$HOMEDIR/blobs/b64"
ballast() { # dir, MB (multiple of 64)
  mkdir -p "$1/node_modules/.cache"; local n=$(( $2 / 64 )) i
  for ((i=0;i<n;i++)); do cp -c "$HOMEDIR/blobs/b64" "$1/node_modules/.cache/pack-$i"; done
}

ts() { date -v-"$1"H "+%Y-%m-%dT%H:%M:00"; }     # hours ago
stamp() { date -v-"$1"H "+%Y%m%d%H%M"; }
commit() { # repo, hours ago, message
  echo "$3 $RANDOM" >> "$1/.history"; git -C "$1" add -A
  GIT_AUTHOR_DATE=$(ts "$2") GIT_COMMITTER_DATE=$(ts "$2") git -C "$1" commit -qm "$3"
}
age() { local g; g=$(git -C "$1" rev-parse --path-format=absolute --git-dir)
  touch -t "$(stamp "$2")" "$g/HEAD" "$g/logs/HEAD" 2>/dev/null || true
  find "$1" -maxdepth 1 -not -name .git -exec touch -h -t "$(stamp "$2")" {} + 2>/dev/null || true; }
repo() { # path, hours ago of last commit, [remote]
  git init -q -b main "$1"; echo "# $(basename "$1")" > "$1/README.md"; printf "node_modules/\n.claude/worktrees/\n" > "$1/.gitignore"
  commit "$1" $(( $2 + 900 )) "Initial commit"; commit "$1" $(( $2 + 200 )) "Set up project"; commit "$1" "$2" "Tidy up"
  if [ "${3:-}" = remote ]; then local n; n=$(basename "$1")
    git init -q --bare -b main "$REM/$n.git"; git -C "$1" remote add origin "$REM/$n.git"
    git -C "$1" push -qu origin main; git -C "$1" remote set-head origin main; fi
}
wt() { git -C "$1" worktree add -q -b "$2" "$3"; }

# ── tidepool: the main project, an agent's playground ───────────────────────
T="$CODE/tidepool"; repo "$T" 3 remote; ballast "$T" 1408
mkdir -p "$T/.claude/worktrees"
wt "$T" claude/fix-flaky-upload-test "$T/.claude/worktrees/fix-flaky-upload-test"
commit "$T/.claude/worktrees/fix-flaky-upload-test" 190 "Retry upload test on timeout"
git -C "$T/.claude/worktrees/fix-flaky-upload-test" push -qu origin claude/fix-flaky-upload-test
git -C "$T" merge -q --no-edit claude/fix-flaky-upload-test; git -C "$T" push -q origin main
git -C "$T" push -q origin --delete claude/fix-flaky-upload-test; git -C "$T" fetch -q --prune
ballast "$T/.claude/worktrees/fix-flaky-upload-test" 512; age "$T/.claude/worktrees/fix-flaky-upload-test" 190

wt "$T" claude/dark-mode-tokens "$T/.claude/worktrees/dark-mode-tokens"
commit "$T/.claude/worktrees/dark-mode-tokens" 300 "Dark mode tokens"
git -C "$T/.claude/worktrees/dark-mode-tokens" push -qu origin claude/dark-mode-tokens
git -C "$T" push -q origin --delete claude/dark-mode-tokens; git -C "$T" fetch -q --prune
ballast "$T/.claude/worktrees/dark-mode-tokens" 448; age "$T/.claude/worktrees/dark-mode-tokens" 300

wt "$T" claude/refactor-sync-engine "$T/.claude/worktrees/refactor-sync-engine"
commit "$T/.claude/worktrees/refactor-sync-engine" 2 "Split sync engine into stages"
commit "$T/.claude/worktrees/refactor-sync-engine" 1 "Move retries into the queue"
echo "wip" >> "$T/.claude/worktrees/refactor-sync-engine/README.md"; echo "todo" > "$T/.claude/worktrees/refactor-sync-engine/NOTES.md"
ballast "$T/.claude/worktrees/refactor-sync-engine" 512

wt "$T" claude/review-pr-212 "$T/.claude/worktrees/review-pr-212"
commit "$T/.claude/worktrees/review-pr-212" 520 "Review notes"
git -C "$T/.claude/worktrees/review-pr-212" push -qu origin claude/review-pr-212
ballast "$T/.claude/worktrees/review-pr-212" 384; age "$T/.claude/worktrees/review-pr-212" 520

wt "$T" claude/onboarding-copy "$T/.claude/worktrees/onboarding-copy"
commit "$T/.claude/worktrees/onboarding-copy" 30 "Rewrite onboarding copy"
ballast "$T/.claude/worktrees/onboarding-copy" 256

wt "$T" claude/old-spike "$T/.claude/worktrees/old-spike"; rm -rf "$T/.claude/worktrees/old-spike"

for b in chore/bump-deps docs/api-examples fix/typo-in-readme; do
  git -C "$T" branch "$b"; git -C "$T" push -q origin "$b"; git -C "$T" push -q origin --delete "$b"; done
git -C "$T" fetch -q --prune; age "$T" 3

# ── marigold-web, with a Codex worktree outside ~/Code ──────────────────────
M="$CODE/marigold-web"; repo "$M" 20 remote; ballast "$M" 960
wt "$M" codex/image-pipeline "$HOMEDIR/.codex/worktrees/marigold-image-pipeline"
commit "$HOMEDIR/.codex/worktrees/marigold-image-pipeline" 70 "Resize images at build time"
git -C "$HOMEDIR/.codex/worktrees/marigold-image-pipeline" push -qu origin codex/image-pipeline
git -C "$M" merge -q --no-edit codex/image-pipeline; git -C "$M" push -q origin main
ballast "$HOMEDIR/.codex/worktrees/marigold-image-pipeline" 640; age "$HOMEDIR/.codex/worktrees/marigold-image-pipeline" 70
age "$M" 20

# ── other active work ───────────────────────────────────────────────────────
L="$CODE/lantern-cli"; repo "$L" 5 remote; echo "edit" >> "$L/README.md"; echo "x" > "$L/flags.rs"
D="$CODE/dotfiles"; repo "$D" 26 remote; age "$D" 26
H="$CODE/workshop-zine"; repo "$H" 50 remote; ballast "$H" 192; commit "$H" 40 "Add step 3 screenshots"; age "$H" 40

# ── idle ────────────────────────────────────────────────────────────────────
P="$CODE/paper-planes"; repo "$P" 400 remote; ballast "$P" 320; age "$P" 400
Q="$CODE/quill-notes"; repo "$Q" 600; age "$Q" 600
mkdir -p "$CODE/clients"
repo "$CODE/clients/harbor-booking" 330 remote; ballast "$CODE/clients/harbor-booking" 704; age "$CODE/clients/harbor-booking" 330
repo "$CODE/clients/fernwood-dashboard" 90 remote; ballast "$CODE/clients/fernwood-dashboard" 448; age "$CODE/clients/fernwood-dashboard" 90

# ── dormant ─────────────────────────────────────────────────────────────────
for spec in "pixel-garden 5200 1152" "retro-weather 9600 576" "advent-of-code-2024 7800 128" "old-portfolio 14000 512"; do
  set -- $spec; repo "$CODE/$1" "$2" remote; ballast "$CODE/$1" "$3"; age "$CODE/$1" "$2"; done
S="$CODE/hackathon-scrapbot"; repo "$S" 6000 remote; ballast "$S" 1024
commit "$S" 5800 "Demo-day hacks"; commit "$S" 5790 "Last-minute fix"; age "$S" 5790
G="$CODE/synth-sketches"; repo "$G" 4300; ballast "$G" 256; age "$G" 4300

# ── not in git ──────────────────────────────────────────────────────────────
for spec in "screenshots-2025 768 2900" "scratch 64 200" "figma-exports 384 3600" "downloads-to-sort 192 7000"; do
  set -- $spec; mkdir -p "$CODE/$1"; ballast "$CODE/$1" "$2"
  find "$CODE/$1" -exec touch -h -t "$(stamp "$3")" {} +; done

echo "$CODE"
