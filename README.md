# Grove

A native macOS app for tending a messy `~/Code` folder: every repository, every worktree (including the ones tucked away in `.claude/worktrees` or outside the folder entirely), and every loose folder that isn't in git — with a clear read on what's active, what's gone stale, and what's safe to clear out.

## Install

**[Download Grove.pkg](https://github.com/leowilkin/grove/releases/latest/download/Grove.pkg)** and open it. It installs Grove into Applications. Needs an Apple silicon Mac on macOS 26 or later.

Releases aren't signed with a Developer ID yet, so the first time you open the installer macOS says it can't verify it. Click **Done**, then open **System Settings → Privacy & Security**, scroll down to the message about Grove.pkg, and click **Open Anyway**.

Or install from the terminal, which skips that (`curl` doesn't mark the download as quarantined):

```bash
curl -LO https://github.com/leowilkin/grove/releases/latest/download/Grove.pkg && sudo installer -pkg Grove.pkg -target /
```

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
- **Pin** a repository to keep it in the sidebar and out of every removal suggestion. Its stale branches can still be cleaned up.
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

## Releasing

```bash
./scripts/build-pkg.sh 1.2.0      # builds build/Grove.pkg, stamped 1.2.0
```

Local builds are signed ad hoc, which only satisfies Gatekeeper on the Mac that built them.

Pushing a tag like `v1.2.0` runs the Release workflow, which builds the installer on a macOS 26 runner and attaches `Grove.pkg` to a GitHub release for that tag. The download link above always points at the newest release. Running the workflow by hand from the Actions tab does the same but attaches the installer to the run instead of publishing it.

Once the signing secrets below are set, the workflow also signs the app and installer with The Hack Foundation's Developer ID and notarizes them; without them it publishes unsigned. To set them up:

1. Get a **Developer ID Application** and a **Developer ID Installer** certificate from that team into your keychain. An Apple Development certificate won't do.
2. In Keychain Access, select both, export them together as one `.p12`, then:

   ```bash
   base64 -i developer-id.p12 | gh secret set DEVELOPER_ID_P12
   ```

   ```bash
   gh secret set DEVELOPER_ID_P12_PASSWORD
   ```

3. For notarization, an admin creates a team key in App Store Connect under **Users and Access → Integrations → App Store Connect API** (the Developer role is enough) and downloads its `.p8`, which Apple only lets you download once:

   ```bash
   gh secret set NOTARY_KEY < AuthKey_XXXXXXXXXX.p8
   ```

   ```bash
   gh secret set NOTARY_KEY_ID
   ```

   ```bash
   gh secret set NOTARY_ISSUER_ID
   ```

`gh secret set` prompts for the value when nothing is piped in. The key ID is listed next to the key, and the issuer ID is shown above the list.

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
