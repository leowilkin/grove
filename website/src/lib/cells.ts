import folder from '../data/demo-folder.json';

export type State = 'active' | 'idle' | 'dormant' | 'folder' | 'missing';
export type Verdict = 'ready' | 'attention' | 'keep' | 'loose';

export interface Item {
  name: string;
  kind: 'repository' | 'worktree' | 'folder';
  path: string;
  branch: string | null;
  size: number;
  sizeLabel: string;
  when: string;
  state: State;
  verdict: Verdict;
  why: string;
  inside: boolean;
  nestedIn: string | null;
}

export const items = folder as Item[];

// 5×7 letters on the construction grid. Square cells only: the diagonal is reserved for what Grove would clear.
const GLYPHS: Record<string, string[]> = {
  G: ['#####', '#....', '#....', '#.###', '#...#', '#...#', '#####'],
  R: ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  O: ['#####', '#...#', '#...#', '#...#', '#...#', '#...#', '#####'],
  V: ['#...#', '#...#', '#...#', '#...#', '.#.#.', '.#.#.', '..#..'],
  E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  T: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  I: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'],
  D: ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  Y: ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
};

export const ROWS = 7;

export interface Cell {
  col: number;
  row: number;
  item: number | null; // index into `items`, or null for a plain (mono) cell
}

/** Lit cells of a word, in column-major order so colour sweeps left to right like Grove's storage bar. */
export function layout(word: string): { cols: number; cells: Omit<Cell, 'item'>[] } {
  const cells: Omit<Cell, 'item'>[] = [];
  let x = 0;
  for (const letter of word) {
    const g = GLYPHS[letter];
    for (let c = 0; c < 5; c++) {
      for (let r = 0; r < ROWS; r++) if (g[r][c] === '#') cells.push({ col: x + c, row: r });
    }
    x += 6;
  }
  return { cols: x - 1, cells };
}

const stateOrder: State[] = ['active', 'idle', 'dormant', 'folder', 'missing'];

/** Items in storage-bar order, each repository followed by its worktrees. */
export function ordered(list: number[]): number[] {
  const heads = list.filter((i) => {
    const it = items[i];
    return !(it.kind === 'worktree' && ownerOf(i) !== null && list.includes(ownerOf(i)!));
  });
  const groupSize = (h: number) => [h, ...list.filter((i) => ownerOf(i) === h)].reduce((s, i) => s + items[i].size, 0);
  heads.sort((a, b) => {
    const s = stateOrder.indexOf(items[a].state) - stateOrder.indexOf(items[b].state);
    return s !== 0 ? s : groupSize(b) - groupSize(a);
  });
  const out: number[] = [];
  for (const h of heads) {
    out.push(h);
    const kids = list.filter((i) => ownerOf(i) === h && i !== h);
    kids.sort((a, b) => stateOrder.indexOf(items[a].state) - stateOrder.indexOf(items[b].state) || items[b].size - items[a].size);
    out.push(...kids);
  }
  return out;
}

/** The repository a worktree belongs to: nested inside it, or sharing its name as a prefix when it lives elsewhere. */
function ownerOf(i: number): number | null {
  const it = items[i];
  if (it.kind !== 'worktree') return null;
  const owner = items.findIndex(
    (r) =>
      r.kind === 'repository' &&
      (it.path.startsWith(r.path + '/') || (!it.inside && it.name.startsWith(r.name.split('-')[0] + '-'))),
  );
  return owner >= 0 ? owner : null;
}

/** Share a word's lit cells among items by disk size: one cell each, the rest by largest remainder. */
export function allocate(word: string, list: number[]): { cols: number; cells: Cell[] } {
  const { cols, cells } = layout(word);
  const order = ordered(list);
  const spare = cells.length - order.length;
  const total = order.reduce((s, i) => s + items[i].size, 0);
  const exact = order.map((i) => (items[i].size / total) * spare);
  const counts = exact.map((e) => 1 + Math.floor(e));
  let left = cells.length - counts.reduce((a, b) => a + b, 0);
  const byRemainder = exact.map((e, k) => [e - Math.floor(e), k] as const).sort((a, b) => b[0] - a[0]);
  for (let n = 0; left > 0; n++, left--) counts[byRemainder[n % byRemainder.length][1]]++;
  let k = 0;
  const assigned: Cell[] = [];
  order.forEach((i, n) => {
    for (let c = 0; c < counts[n]; c++) assigned.push({ ...cells[k++], item: i });
  });
  return { cols, cells: assigned };
}

export const bytes = (b: number) =>
  b >= 1e9 ? `${(b / 1e9).toFixed(2)}\u00a0GB` : b >= 1e6 ? `${Math.round(b / 1e6)}\u00a0MB` : `${Math.round(b / 1e3)}\u00a0KB`;

export const all = items.map((_, i) => i);
export const ready = all.filter((i) => items[i].verdict === 'ready');
export const kept = all.filter((i) => items[i].verdict !== 'ready');
export const sum = (list: number[]) => list.reduce((s, i) => s + items[i].size, 0);
export const byState = (state: State, list = all) => sum(list.filter((i) => items[i].state === state));
