---
version: 1
slug: "website-src-pages-index-astro"
primary_target: "website/src/pages/index.astro"
related_targets: []
---

# Landing page

Scope: the marketing site's single landing page (`website/`, Astro). Visitor mode: Persuade.

Audience: Mac developers whose `~/Code` has outgrown their memory, agent-heavy developers first (worktrees under `.claude/worktrees`, `~/.codex/worktrees`), any messy code folder second.
Action: download the .dmg (placeholder URL until a release ships); secondary: source on GitHub.
Proof on hand: real screenshots of Grove scanning a fictional demo folder (`fern` fixture: 26 items, 11.75 GB, 9 ready to remove), and Grove's own scan data for that folder. Label the demo folder as fictional. No testimonials, counts, prices or versions.
Constraints: no PII; product claims only from README/PRODUCT.md.

## Direction contract

THESIS: The folder as a visible construction grid. Every repository, worktree and loose folder is a cell, coloured by its state, its share of cells set by disk size; the word GROVE is built from the demo folder itself. Refuses the Mac-utility default of a centred icon, headline, download button and window screenshot over a row of feature cards.

OWN-WORLD: Crouwel gridded specimen on Grove green. Deep green ground (#0b4f33 family) with white construction-grid hairlines; white specimen-paper sheets with faint green-grey grid for reading passages (ink sheets in dark mode). Grid-constructed cell letters for the monumental moments only; a neutral grotesk (Schibsted Grotesk) for text; JetBrains Mono strictly for paths, branches and sizes. Four state colours (active leaf green, idle blue, dormant orange, not-in-git pale grey) mean the same thing everywhere. The diagonal is the one rebellion and has one meaning: a diagonal stroke marks what Grove would clear (and the branch line it came from). Square corners, hairlines, no shadows except the app plate.

STORY: In one viewport the visitor sees their kind of folder read as a grid, learns Grove sorts it by what git says, and can clear the finished cells and undo it. Below: how Grove reads git (field marks on the real app), the agent-worktree mess sorted line by line, the safety rules, then download.

FIRST VIEWPORT: 1440×900 green sheet, visible 36px grid. Top bar: cell wordmark left, three links and a white Download button right. GROVE in cell letters spans ~1040px across the upper half, 7 cells tall, each cell a demo-folder item at ~132 MB per cell, ordered like Grove's storage bar (active → idle → dormant → not in git), clearable cells slashed. Below-left: headline (~64px) and one sentence, the primary Download button and a GitHub link. Right: a readout panel bound to the hovered/focused cell (name, path, branch, size, last activity, Grove's verdict) and the signature control "Clear 9 finished items" → cells vacate, total ticks 11.75 GB → 7.19 GB, Undo (⌘Z) restores. One long diagonal branch line crosses the sheet.

FORM: Grid Specimen (Crouwel gridded type specimen), dealt challenger, user-chosen over the assigned Moving Day (my grounded list ran 1 field guide, 2 park brochure, 3 tree survey, 4 library weeding, 5 moving day, 6 transit diagram, 7 split-flap). Seed key eddcbe44. Kept from declined challengers: select one item, dim the rest, bring its facts forward (event display); every action shown as before → after with real numbers (forge).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
