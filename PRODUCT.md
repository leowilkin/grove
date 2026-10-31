# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The product itself is a native macOS app (SwiftUI, macOS 26+). `web` here covers the marketing site in `website/`; design work on the app follows macOS conventions.

## Stack

Astro, in `website/`. Deploy target not decided.

## Users

Developers on a Mac whose code folder (usually `~/Code`) has grown past what they can hold in their head. First audience: people who work alongside coding agents (Claude Code, Codex and similar), whose folder fills with worktrees, half-finished branches and review checkouts the agents leave behind, often tucked inside `.claude/worktrees` or outside the folder entirely. Second audience: any developer with years of repositories piling up in one place. Lead with the agent-worktree mess; make clear it works for any messy code folder.

## Product Purpose

Grove gives one clear read on a code folder: every repository, every worktree, every loose folder that isn't in git; what's active, what's gone stale, what's safe to clear out; and then lets you clear it out without fear. Success is a folder you trust again, and disk space back, without ever losing work.

## Positioning

Grove understands git, not just disk usage. It knows a worktree whose branch was merged or whose remote branch was deleted is finished; that a dormant repository with every commit on a remote is safe to remove; that a branch checked out somewhere must never be touched. Cleanup goes through the real Trash with ⌘Z undo, including git's own worktree records. A disk-space tool sees folders; Grove sees work.

## Operating Context

- Scans a root folder (default `~/Code`, changeable in Settings) read-only, with `GIT_OPTIONAL_LOCKS=0` so it never takes the index lock from an open editor or terminal.
- Finds worktrees wherever git put them, including `.claude/worktrees` and paths outside the root.
- "Last activity" is the latest of the last commit, the last HEAD movement, and edits to uncommitted files. A repository is as active as its busiest worktree.
- Opens items in Finder, the user's editor, terminal, or the remote on GitHub.
- Keyboard-driven: ⌘R refresh, ⌥⌘R fetch all, ⌘⌫ move to Trash, ⌘Z undo, ⌥⌘I inspector, and more.

## Capabilities and Constraints

- Overview: disk use split by activity (active, idle, dormant, not in git), counts, and recommendations: finished worktrees, dormant fully-pushed repositories, stale local branches, worktrees git tracks whose folders are gone, uncommitted or unpushed work, folders nothing backs up.
- Library with smart filters (repositories, worktrees, other folders, needs attention, recently active, dormant, ready to remove) and sorting by name, branch, status, last activity, size.
- Inspector: branch and tracking, working tree state, commits not on any remote, last commit, a repository's worktrees and branches.
- Safety: Move to Trash uses the real Trash (Finder's Put Back works) and ⌘Z undoes it; removing a worktree sets aside git's record so undo restores it exactly (records cleared after a week); removing a repository lists every linked worktree it takes; uncommitted, unpushed, stashed or remote-less work is called out before confirming; branch cleanup never touches the default, current, or any checked-out branch, and deleted branches restore with ⌘Z; Pin keeps a repository out of every suggestion; Fetch All is the only network action on repositories and only runs when clicked.
- Updates: once a day the copy in Applications checks GitHub for a newer release and offers to install it (password prompt, then Grove reopens). The check can be turned off in Settings; Grove → Check for Updates… runs it on demand.
- Requires macOS 26 or later.
- Distribution: Grove.pkg on GitHub releases, unsigned until Developer ID signing is set up.
- Undecided: license, price (assume nothing), version number for launch, deploy target for the site.

## Brand Commitments

- Name: Grove. Tagline in the app bundle: "A place to tend your repositories."
- App icon: a white git graph growing like a tree (tapered trunk, two curling branches, three commit nodes, a ground line) on a green squircle. Drawn by `scripts/make-icon.swift`.
- The app's own vocabulary: tend, grove, "Your grove is tidy", leaf symbol for cleanup.
- The organisation is Hack Club, written exactly "Hack Club".

## Evidence on Hand

- The running app on the maintainer's Mac; screenshots can be captured from it, pointed at fictional fixture folders (`scripts/make-fixtures.sh`), never at a real code folder.
- The README's feature and safety lists are the factual source for claims.
- No testimonials, user counts, press, benchmarks, or download numbers exist. Do not invent them.

## Product Principles

- Never lose work: every destructive action is reversible or called out first.
- Read-only until asked: scanning never changes anything, and the network is touched only on request, apart from a daily update check that can be turned off.
- Understand git, not just folders: recommendations come from branch and remote state, not from size alone.
- Clear read first, action second: the overview tells you what's true before suggesting what to do.
