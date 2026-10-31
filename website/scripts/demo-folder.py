# Turns Grove's scan cache of the showcase folder into src/data/demo-folder.json.
# Usage: python3 scripts/demo-folder.py <Grove cache .json> <fake home> src/data/demo-folder.json
# Paths under <fake home> become ~/…; verdicts mirror GroveStore's cleanupReason and needsAttention.
import json, sys, time
src, fake_home, out = sys.argv[1], sys.argv[2], sys.argv[3]
items = json.load(open(src))
REF = 978307200  # Foundation reference date
now = time.time()
def tilde(p): return '~' + p[len(fake_home):] if p.startswith(fake_home) else p
def ago(d):
    if d < 1: return 'Today'
    if d < 2: return 'Yesterday'
    if d < 45: return f'{int(d)} days ago'
    m = round(d / 30.4)
    return f'{m} months ago' if m < 12 else f'{round(d/365)} year ago' if round(d/365) == 1 else f'{round(d/365)} years ago'
def mb(b): return f'{b/1e9:.2f} GB' if b >= 1e9 else f'{b/1e6:.0f} MB' if b >= 1e6 else f'{b/1e3:.0f} KB'
by_path = {it['path']: it for it in items}
rows = []
for it in items:
    g = it.get('git') or {}
    kind = it['kind']; missing = it.get('isMissing', False)
    la = it.get('lastActivity'); days = (now - (la + REF)) / 86400 if la else None
    state = 'folder' if kind == 'folder' else 'missing' if missing else 'active' if days <= 14 else 'dormant' if days > 90 else 'idle'
    size = it.get('size') or 0
    remote = bool(g.get('remoteURL')); ch = g.get('changes', 0) + g.get('untracked', 0)
    unp = g.get('unpushed', 0); unp_all = g.get('unpushedAllBranches', 0)
    verdict, why = 'keep', ''
    if kind == 'folder':
        verdict, why = 'loose', "Not a git repository, so nothing backs it up."
    elif missing:
        verdict, why = 'ready', "Folder deleted, but git still tracks the worktree. Grove can forget it."
    elif kind == 'worktree':
        if ch: verdict, why = 'attention', f"{ch} uncommitted change{'s' if ch>1 else ''}" + (f", {unp} commit{'s' if unp>1 else ''} not on any remote." if unp else '.')
        elif g.get('isMerged'): verdict, why = 'ready', "Branch merged into main, nothing uncommitted."
        elif g.get('upstreamGone'): verdict, why = 'ready', "Remote branch deleted after its pull request closed, nothing uncommitted."
        elif remote and unp == 0 and state != 'active': verdict, why = 'ready', f"Idle {int(days)} days with everything pushed."
        elif unp: verdict, why = 'attention', f"{unp} commit{'s' if unp>1 else ''} not on any remote yet."
        else: why = "In use."
    else:
        if ch: verdict, why = 'attention', f"{ch} uncommitted change{'s' if ch>1 else ''}."
        elif remote and unp: verdict, why = 'attention', f"{unp} commit{'s' if unp>1 else ''} not on any remote yet."
        elif state == 'dormant' and remote and unp_all == 0: verdict, why = 'ready', f"Untouched for {int(days)} days, every commit already on a remote."
        elif not remote: verdict, why = 'keep', "No remote, so this is the only copy. Grove won't suggest removing it."
        elif unp_all: verdict, why = "keep", f"Everything on {g.get('branch')} is pushed. {unp_all} commits on its agent branches aren't on any remote yet."
        else: why = "Everything is pushed." if state != 'dormant' else "Dormant."
    rows.append(dict(name=it['name'], kind=kind, path=tilde(it['path']), branch=g.get('branch'), size=size, sizeLabel=mb(size) if size else '—',
        when=ago(days) if days is not None else 'Folder missing', state=state, verdict=verdict, why=why,
        inside=it.get('isInsideRoot', True), nestedIn=None))
# nested worktrees: subtract from their parent repo so the word never counts bytes twice
for r in rows:
    if r['kind'] == 'worktree' and r['inside'] and r['size']:
        parent = next((p for p in rows if p['kind'] == 'repository' and r['path'].startswith(p['path'] + '/')), None)
        if parent: parent['size'] -= r['size']; r['nestedIn'] = parent['name']
for r in rows:
    if r['kind'] == 'repository': r['sizeLabel'] = mb(r['size'])
json.dump(rows, open(out, 'w'), indent=1)
tot = sum(r['size'] for r in rows); ready = [r for r in rows if r['verdict'] == 'ready']
print(len(rows), 'items', mb(tot), '| ready', len(ready), mb(sum(r['size'] for r in ready)))
for r in rows: print(f"{r['state']:8} {r['verdict']:9} {r['sizeLabel']:>8} {r['when']:>13}  {r['path']}  [{r['branch']}]  {r['why']}")
