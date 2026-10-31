# Grove

A native macOS app for tending a messy `~/Code` folder: every repository, every worktree (including the ones tucked away in `.claude/worktrees` or outside the folder entirely), and every loose folder that isn't in git — with a clear read on what's active, what's gone stale, and what's safe to clear out.

## What it shows

- **Overview**: disk use split by activity (active, idle, dormant, not in git), counts, and recommendations:
  - finished worktrees (branch merged, remote branch deleted, or idle with everything pushed)
  - dormant repositories whose every commit is already on a remote
  - stale local branches (merged, or their remote branch was deleted)
  - worktrees git still tracks after their folder was deleted
  - uncommitted or unpushed work, and folders nothing backs up
- **Library and smart filters**: repositories, worktrees, other folders, needs attention, recently active, dormant, ready to remove. Sort by name, branch, status, last activity, or size.
- **Inspector**: branch and tracking, working tree state, commits not on any remote, last commit, a repository's worktrees and branches, and one-click open in Finder, your editor, your terminal, or the remote on GitHub.

"Last activity" is the latest of the last commit, the last HEAD movement (commit, checkout, pull), and edits to uncommitted files. A repository is as active as its busiest worktree.

## Safety

- Scanning is read-only. Git runs with `GIT_OPTIONAL_LOCKS=0`, so Grove never takes the index lock out from under your editor or terminal.
- **Move to Trash** uses the real Trash, so Finder's Put Back works, and **⌘Z** undoes it. Removing a worktree also sets aside git's record of it (equivalent to `git worktree prune`) so undo can put it back exactly; those records are cleared after a week.
- Removing a repository takes its linked worktrees with it, and the confirmation lists every one.
- Anything with uncommitted changes, unpushed commits, stashes, or no remote is called out before you confirm.
- Branch cleanup never touches the default branch, the current branch, or a branch checked out in any worktree. Deleted branches can be restored with ⌘Z.
- **Pin** a repository to keep it in the sidebar and out of every cleanup suggestion.
- **Fetch All** is the only network action, and it only runs when you click it.

## Build and run

Requires macOS 26 or later and Xcode 26+.

```bash
./scripts/build-app.sh            # builds build/Grove.app
./scripts/build-app.sh --install  # also copies it to ~/Applications
open build/Grove.app
```

Grove looks at `~/Code` by default; change it in Settings (⌘,). To point a single run elsewhere:

```bash
open build/Grove.app --args -rootPath /path/to/folder
```

Set `GROVE_DEBUG=1` in the environment to log failing git calls to stderr.

## Tests

```bash
swift test
```

The tests build throwaway repositories with `scripts/make-fixtures.sh` (merged, remote-deleted, missing, dirty, dormant, grouped and external worktrees), scan them, and run trash → undo and branch delete → undo against real git. One test hosts the table in a window and trashes the selected row, guarding against a crash where table cells lost their environment.

To try the cleanup actions by hand without touching your real folder:

```bash
./scripts/make-fixtures.sh /tmp/grove-fixture
open build/Grove.app --args -rootPath /tmp/grove-fixture/code
```

## Keyboard

| | |
|---|---|
| ⌘R | Refresh |
| ⌥⌘R | Fetch all remotes |
| ⌘O | Open in editor |
| ⇧⌘T | Open in terminal |
| ⇧⌘R | Show in Finder |
| ⇧⌘B | Open remote in browser |
| ⌘⌫ | Move to Trash |
| ⌘Z | Undo the last removal |
| ⌥⌘I | Show or hide the inspector |
