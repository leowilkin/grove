---
name: Grove website
description: The marketing site for Grove, drawn as a gridded type specimen on Grove green, where the folder itself is the grid.
colors:
  grove-green: "#0b4a31"
  grove-green-deep: "#083b27"
  leaf: "#6be38f"
  sheet-white: "#f3faf5"
  green-line: "rgb(255 255 255 / 0.1)"
  green-line-strong: "rgb(255 255 255 / 0.3)"
  green-fg-2: "#b2d5bf"
  green-dim: "#1d5a40"
  button-ink: "#06301f"
  idle-on-green: "#7eabff"
  dormant-on-green: "#ffa24c"
  folder-on-green: "#cdd8d1"
  paper: "#f4f7f3"
  paper-line: "#e0e8e2"
  paper-line-strong: "#b7c5bb"
  paper-ink: "#0c1912"
  paper-ink-2: "#46574d"
  active-on-paper: "#2a9a54"
  idle-on-paper: "#2e6cdb"
  dormant-on-paper: "#dc7716"
  folder-on-paper: "#9ba69f"
  paper-focus: "#127a4a"
  ink: "#0c1410"
  ink-line: "#18241d"
  ink-line-strong: "#33463a"
  ink-fg: "#e6efe9"
  ink-fg-2: "#9cb0a4"
  folder-on-ink: "#8d9b93"
typography:
  display:
    fontFamily: "Schibsted Grotesk Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(2.3rem, 1rem + 3.6vw, 4.4rem)"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Schibsted Grotesk Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(2rem, 1.2rem + 2.3vw, 3.4rem)"
    fontWeight: 700
    lineHeight: 1.02
    letterSpacing: "-0.03em"
  lede:
    fontFamily: "Schibsted Grotesk Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "clamp(1.1rem, 1rem + 0.35vw, 1.3rem)"
    fontWeight: 400
    lineHeight: 1.5
  title:
    fontFamily: "Schibsted Grotesk Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.12rem"
    fontWeight: 650
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Schibsted Grotesk Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Schibsted Grotesk Variable, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.85rem"
    fontWeight: 600
  mono:
    fontFamily: "JetBrains Mono Variable, ui-monospace, monospace"
    fontSize: "0.86em"
    fontFeature: "'liga' 0, 'calt' 0"
  figure:
    fontFamily: "JetBrains Mono Variable, ui-monospace, monospace"
    fontSize: "clamp(2rem, 1.5rem + 1.3vw, 2.8rem)"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "-0.04em"
    fontFeature: "'tnum' 1"
rounded:
  none: "0px"
spacing:
  gutter: "clamp(16px, 4.5vw, 72px)"
  module: "max(10px, min(44px, calc((100vw - 2 * var(--gutter)) / 29), calc((100svh - 470px) / 7)))"
  wrap: "calc(var(--m) * 29)"
  half: "calc(var(--m) * 0.5)"
  three-quarter: "calc(var(--m) * 0.75)"
  block: "calc(var(--m) * 2)"
  sheet-pad: "calc(var(--m) * 3)"
components:
  button-primary:
    backgroundColor: "{colors.sheet-white}"
    textColor: "{colors.button-ink}"
    rounded: "{rounded.none}"
    padding: "0 1.3em 0 1.15em"
    height: "max(48px, calc(var(--m) * 1.5))"
  button-primary-hover:
    backgroundColor: "{colors.leaf}"
    textColor: "{colors.button-ink}"
  button-primary-compact:
    backgroundColor: "{colors.sheet-white}"
    textColor: "{colors.button-ink}"
    rounded: "{rounded.none}"
    height: "max(40px, var(--m))"
  button-quiet:
    backgroundColor: "transparent"
    textColor: "{colors.sheet-white}"
    rounded: "{rounded.none}"
    padding: "0 1.3em 0 1.15em"
    height: "max(48px, calc(var(--m) * 1.5))"
  button-quiet-undo:
    backgroundColor: "{colors.sheet-white}"
    textColor: "{colors.button-ink}"
  nav-link:
    textColor: "{colors.green-fg-2}"
    typography: "{typography.body}"
  nav-link-hover:
    textColor: "{colors.sheet-white}"
  readout-panel:
    backgroundColor: "{colors.grove-green}"
    textColor: "{colors.sheet-white}"
    rounded: "{rounded.none}"
    padding: "calc(var(--m) * 0.5)"
    width: "calc(var(--m) * 10)"
  cell:
    rounded: "{rounded.none}"
    size: "var(--m)"
  state-mark:
    rounded: "{rounded.none}"
    size: "max(18px, calc(var(--m) * 0.6))"
  key-cap:
    backgroundColor: "transparent"
    rounded: "{rounded.none}"
    height: "1.9em"
    padding: "0 0.35em"
---

# Design System: Grove website

This system governs the marketing site in `website/` only. The Grove app is a native macOS SwiftUI app and follows macOS conventions; nothing here applies to its interface.

## Overview

**Creative North Star: "The Folder as Specimen Grid"**

The site is a gridded type specimen printed on Grove green. Every section is a sheet with its construction grid left visible: hairlines at one module apart, a module sized so that exactly 29 of them span the page. The monumental words are not set in a font at all; they are built from square cells on that grid, and in the hero each cell is a real item from a demo folder, coloured by its state and sized by its share of disk. Everything else is a calm, neutral grotesk doing editorial work in the margins of that grid.

The world alternates two kinds of sheet. Green sheets carry the specimen moments (the hero, the agent worktree table, the close) and stay green in both colour schemes. Paper sheets carry the long reading passages (how Grove reads git, the safety rules) and turn from pale paper to green-black ink when the visitor's system is in dark mode. Components never pick their own colours; they read whatever the sheet beneath them supplies.

Density is that of a reference sheet rather than a brochure: tables with hairline rules, definition lists, real paths and real sizes in monospace, numbers that tick when something is cleared. Ornament is limited to what carries meaning: the grid, the four state colours, and one diagonal stroke.

**Key Characteristics:**
- A single fluid module (10–44px) sets the grid, the cell size, the wrap width (29 modules) and most spacing.
- Visible construction hairlines on every sheet, running through the cell letters as well.
- Four state colours plus a dashed outline for "missing", identical in meaning on every sheet.
- Square corners and hairline borders throughout; flat surfaces; one shadow, under the app screenshot.
- Grotesk for all text, monospace only for paths, branches, sizes and totals.

## Colors

A deep forest green ground with near-white type, a pale green-grey paper for reading, and four saturated state colours that only ever mean folder state.

### Primary
- **Grove Green** (grove-green): the ground of every green sheet, the page background behind everything, and the browser theme colour. It is the brand.
- **Leaf** (leaf): the active-state colour on green and ink sheets; also the hover fill of the primary button and the text-selection highlight, the only places it appears without meaning "active".
- **Sheet White** (sheet-white): text on green and the fill of the primary button. A green-tinted white, never pure white.

### Secondary (state colours)
State colours come in a set per sheet, tuned for that ground; the meaning never changes.
- **Active**: leaf on green and ink; Deep Leaf (active-on-paper) on paper.
- **Idle**: Signal Blue (idle-on-green, also on ink); Deep Signal Blue (idle-on-paper) on paper.
- **Dormant**: Late Orange (dormant-on-green, also on ink); Burnt Orange (dormant-on-paper) on paper.
- **Not in git**: Lichen Grey (folder-on-green), Stone Grey (folder-on-paper), Slate Grey (folder-on-ink).
- **Missing** has no fill: a 1px dashed outline in the sheet's secondary text colour.

### Neutral
- **Green Hairline** (green-line) and **Strong Green Hairline** (green-line-strong): the construction grid and the structural rules (top bar, panel borders, sheet seams) on green.
- **Pale Sage** (green-fg-2): secondary text, nav links, captions on green.
- **Shade Green** (green-dim): the tint laid over every cell that is not the one being read.
- **Button Ink** (button-ink): text on any white or leaf fill.
- **Grove Green Deep** (grove-green-deep): the scrollbar track.
- **Paper** (paper), **Paper Hairline** (paper-line), **Strong Paper Hairline** (paper-line-strong), **Paper Ink** (paper-ink), **Paper Ink Secondary** (paper-ink-2), **Paper Focus** (paper-focus): the light reading sheet.
- **Ink** (ink), **Ink Hairline** (ink-line), **Strong Ink Hairline** (ink-line-strong), **Ink Text** (ink-fg), **Ink Text Secondary** (ink-fg-2): the same reading sheet under dark mode; its focus ring is leaf.

### Named Rules
**The State Colour Rule.** Active, idle, dormant and not-in-git colours mean exactly that, wherever they appear: cells, swatches, table marks, the key. Never use a state colour to decorate, categorise or highlight anything else (leaf's role as button hover and selection is the one standing exception).

**The Sheet Owns the Palette Rule.** Every section is a `sheet-green` or `sheet-paper`; the sheet sets ground, hairlines, text, state colours, slash and focus as custom properties, and components only read them. A new component that hard-codes a colour is wrong on one of the two sheets.

**The Green Stays Green Rule.** Green sheets keep their ground in dark mode; only paper sheets flip, to ink.

## Typography

**Display Font:** Schibsted Grotesk Variable (with ui-sans-serif, system-ui)
**Body Font:** Schibsted Grotesk Variable
**Label/Mono Font:** JetBrains Mono Variable (with ui-monospace), ligatures off

**Character:** a sober newspaper grotesk set tight and heavy for headlines, open and plain for reading; the mono is a technical instrument for data, not a voice.

### Hierarchy
- **Display** (700, clamp 2.3–4.4rem, 1, -0.035em): the hero headline only, balanced, max about 11em wide.
- **Headline** (700, clamp 2–3.4rem, 1.02, -0.03em): one per sheet, balanced, 14–15em max.
- **Lede** (400, clamp 1.1–1.3rem, 1.5): the paragraph under a headline, in secondary text colour, 30–36em max; inline code inside it goes back to full text colour.
- **Promise** (400, clamp 1.35–2rem, 1.3, -0.015em): a single large statement sentence, used once on the safety sheet.
- **Title** (650, 1–1.2rem, -0.01em): table row heads, definition terms, the small h3; weight 650 is the house emphasis weight.
- **Body** (400, 1.0625rem, 1.55): running text and table cells.
- **Label** (600, 0.85rem, sentence case): table column heads and fact labels, in secondary text colour. Never uppercase, never tracked out.
- **Mono** (0.86em of context): paths, branch names, `.claude/worktrees` style inline code.
- **Figure** (mono 600, clamp 2–2.8rem, -0.04em, tabular): the readout's live disk total. Smaller sizes use the same mono with tabular numerals at 0.9em.

### Named Rules
**The Instrument Mono Rule.** JetBrains Mono is for things a terminal would print: paths, branches, sizes, totals. Headlines, prose, labels and key caps stay in the grotesk.

**The Cell Letter Rule.** Cell letters are for monumental words only: the hero GROVE, the closing TIDY, and the 4px-module wordmark. Glyphs are 5 by 7 cells with one empty column between letters, square cells only (V and Y step down rather than slant). When a cell word is built from data, every lit cell belongs to a real item, allocated by size; never fill one with invented or decorative cells.

## Layout

One fluid module, `--m`, governs the page: the smaller of one twenty-ninth of the content width, one seventh of the viewport height left after 470px of furniture, and 44px, but never under 10px. The content wrap is exactly 29 modules wide and centred; the grid background is offset so its lines align with the wrap's left edge. Spacing is expressed in module multiples: half and three-quarter modules inside blocks, one to two modules between blocks, three modules of padding at the top and bottom of each sheet.

Compositions are asymmetric and grid-snapped: headline left with lede pushed right (13/15 split, or a 14-module indent), the hero's readout panel fixed at 10 modules beside a fluid pitch column. Long content is tables and definition lists ruled with hairlines, a solid text-colour rule over the header row and strong hairlines between rows.

Responsive behaviour: at 860px the hero stacks, the nav links and the cell wordmark give way to a small icon-plus-name mark, and the branch line is hidden; at 960px tables collapse into per-row grids with the state mark in its own column and the safety rules go to one column; at 600px the paper grid doubles its spacing so it reads as a texture rather than noise.

**The Twenty-Nine Rule.** Measure in modules. A width, gap or padding that cannot be stated as a module multiple (or a small fixed text-relative gap inside a line) is out of system.

## Elevation & Depth

The world is flat. Depth comes from sheets meeting at a strong hairline seam (an inset 1px line, not a shadow), from borders, and from tint: when one cell is being read, every other cell is overlaid with shade green so the chosen one comes forward. The one real shadow sits under the app screenshot, because that plate is a photographed object lying on the paper.

### Shadow Vocabulary
- **App plate** (`filter: drop-shadow(0 22px 34px rgb(12 25 18 / 0.18)) drop-shadow(0 2px 4px rgb(12 25 18 / 0.12))`): only under screenshots of the Grove app.

### Named Rules
**The Flat Sheet Rule.** No shadows on panels, buttons, cells or tables. If something must come forward, dim what is behind it.

## Shapes

Square corners everywhere the site draws its own shapes: buttons, panels, cells, swatches, key caps, focus rings. Borders are 1px hairlines; "missing" is a 1px dashed outline. The only rounded shapes are ones macOS draws: the app icon (used as the favicon and the small-screen mark) and the window in the app screenshot. They are artifacts of the product, not a licence for rounding.

The diagonal is reserved. A single stroke from top-left to bottom-right through a cell, swatch or table mark (about 2–2.5px, in the sheet's slash colour) means "Grove would clear this". The only other diagonal on the site is the long hairline branch line crossing the hero sheet, the branch those cleared cells came from.

**The One Diagonal Rule.** A slash means clearable and nothing else. Do not use diagonals for decoration, dividers, glyph construction or emphasis.

## Components

### Buttons
Plain, solid, square slabs; confident weight, no ornament.
- **Shape:** square corners, 1px border slot (transparent unless quiet), height at least 48px or 1.5 modules.
- **Primary:** sheet white with button ink at 1.05rem weight 650; optional 1.15em line icon on the leading side (the download arrow). Used for Download only.
- **Hover / Focus:** primary fills to leaf over 0.25s on the house ease; focus is a 2px outline in the sheet's focus colour, offset 3px.
- **Compact primary:** the top-bar Download, at least 40px or one module tall, 0.97rem.
- **Quiet:** transparent with a strong-hairline border and full text colour; hover darkens the border to text colour. Used for the hero's clear control, which spans the panel and carries a trailing key cap.
- **Committed state:** once the clear has run, the quiet control turns sheet white with button ink and reads "Undo" with its ⌘Z key cap; the inverse fill marks that a reversible action is pending.

### Navigation
- A top bar one module tall (min 56px) on the hero sheet: cell wordmark at a 4px module on the left, three section links in pale sage at 0.97rem weight 500 that brighten to sheet white on hover, compact Download on the right, a full-bleed strong hairline beneath. Below 860px the links hide and the wordmark becomes the app icon plus "Grove" in 700.

### Readout Panel (signature)
The hero's instrument. A 10-module column with a strong hairline border on the sheet ground, padded half a module. At rest it shows the folder: path in mono, the live total in the figure style, a one-line summary, a state key, the clear control and a hint. Pointing at or arrowing to a cell crossfades (0.2s) to that item: kind and last activity, name in a 1.6–2.1rem 700 title, path in mono, branch and size as a two-column fact list under a hairline, then Grove's verdict with its swatch and the reason. Before → after is always shown with real numbers.

### Cell Word (signature)
A CSS grid of module-sized square cells with the construction lines drawn over them in a translucent ground colour. Data cells take their item's state colour, slashed when clearable, dashed when missing; all cells of one item light together when read. Cells assemble from 30% scale with a 9ms per-cell stagger on load; clearing empties the slashed cells left to right at 22ms per cell over 0.6s, leaving a faint dashed outline and slash; undo refills them. Without data the word is plain text colour (the wordmark).

### State Marks and Key
Square swatches (0.95rem in the key, at least 18px or 0.6 module in tables) reuse the cell treatment: state fill, slash for clearable, dashed outline for missing. In the reading tables an outlined empty square marks "Grove shows this but leaves it to you" and the same square slashed marks "Grove clears it".

### Reference Tables
Full-width, collapsed borders, a 1px text-colour rule under sentence-case labels, strong hairlines between rows, row padding of 0.3–0.4 module. First column is the state mark; names and paths in mono; sizes right-aligned in tabular mono; the explanation column in secondary text with a 650-weight verdict word leading it.

### Key Caps
Square, 1.9em, strong-hairline border on the sheet ground, grotesk 600 at 0.85em. Combinations butt together with overlapping 1px borders.

## Do's and Don'ts

### Do:
- **Do** derive every size from the module: cells are one module, the wrap is 29, sheet padding is three.
- **Do** put every section on a sheet and let the sheet supply colour; check new work on green, paper and ink.
- **Do** keep the construction grid visible on every sheet, including through cell letters.
- **Do** show actions as before → after with real numbers from the demo folder, and keep undo visible after any clear.
- **Do** dim the rest (shade green overlay) to bring one item forward.
- **Do** honour reduced motion: transitions and the cell assembly collapse to instant.

### Don't:
- **Don't** round corners on anything the site draws; only the app icon and app screenshots are rounded.
- **Don't** add shadows beyond the app plate's drop shadow.
- **Don't** use a diagonal for anything except "Grove would clear this" and the hero's single branch line.
- **Don't** use a state colour for anything but folder state.
- **Don't** set prose, headings or labels in JetBrains Mono, or paths and sizes in the grotesk.
- **Don't** set running headlines in cell letters or fill data cell words with decorative cells.
- **Don't** apply this system to the Grove macOS app.
