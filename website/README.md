# Grove website

The landing page for Grove, built with Astro.

```bash
npm install
npm run dev      # http://localhost:4321
npm run build    # static site in dist/
```

The download buttons point at the newest GitHub release's `Grove.pkg`; `downloadUrl` and `repoUrl` live in `src/site.ts`.

## Deploying

The site is a static-assets Cloudflare Worker named `grove`, served at https://grove.leowilkin.com (see `wrangler.jsonc`; there is no Worker code, Cloudflare serves `dist/` directly).

```bash
npm run deploy   # astro build && wrangler deploy
```

## The demo folder

The word GROVE at the top of the page is drawn from a fictional code folder: each cell is about 140 MB of one item, coloured by its state, and slashed when Grove would clear it. The screenshots show Grove scanning that same folder, so every number on the page agrees with the app.

To rebuild them after the app changes:

1. `scripts/make-showcase.sh <dir>/fern` builds the folder at `<dir>/fern/Code` (sizes come from APFS clones, so it takes little real disk).
2. Open Grove on it (`-rootPath <dir>/fern/Code`), let it finish measuring sizes, and capture the Overview window in light and dark into `src/assets/screens/`. Grove shows the folder's real path; the current shots display it as `~/Code` by rewriting `-[NSString stringByAbbreviatingWithTildeInPath]` in the capture session only, so the app and its data are untouched.
3. `python3 scripts/demo-folder.py "~/Library/Application Support/Grove/Cache/<key>.json" <dir>/fern src/data/demo-folder.json` regenerates the data the page draws from.
