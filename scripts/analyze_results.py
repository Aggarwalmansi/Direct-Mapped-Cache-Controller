#!/usr/bin/env python3
"""Build reproducible performance and equal-capacity baseline reports."""
import csv
import re
from pathlib import Path
out = Path('reports'); out.mkdir(exist_ok=True)
rows = []
for name in ('sequential', 'random', 'repeated', 'conflict'):
    trace = [int(s.split()[0], 16) for s in Path('traces', name+'.trace').read_text().splitlines() if s.strip() and not s.startswith('#')]
    counts = []
    for ways in (1, 2, 64):
        sets = [[] for _ in range(64//ways)]
        hits = 0
        for addr in trace:
            block = addr//16; bucket = sets[block % len(sets)]
            if block in bucket:
                hits += 1; bucket.remove(block)
            elif len(bucket) == ways:
                bucket.pop(0)
            bucket.append(block)
        counts.append(hits)
    annotated = sum(int(s.split()[2]) for s in Path('traces', name+'.trace').read_text().splitlines() if s.strip() and not s.startswith('#'))
    assert counts[0] == annotated
    for latency in (0, 1, 5):
        n = len(trace); miss = n-counts[0]
        # Derived from controller and four sequential word transactions.
        amat = 2 + miss/n*(7+4*latency)
        rows.append([name, latency, n, counts[0], miss, counts[0]/n, amat, counts[1]/n, counts[2]/n])
# Require all measured summary rows to match the independent reference.
log = (out/'simulation.log').read_text()
for name,l,n,h,m,r,a,t,f in rows:
    pattern = rf"^{name}\s+{l}\s+{n}\s+{h}\s+{m}\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)"
    match = re.search(pattern, log, re.M)
    assert match, f'Missing measured result: {name}, latency {l}'
    assert abs(float(match[5])-a) < .001, f'AMAT mismatch: {name}, {l}'
with (out/'performance.csv').open('w') as f:
    w=csv.writer(f); w.writerow(['trace','word_latency','requests','hits','misses','hit_ratio','amat_cycles','two_way_hit_ratio','fully_associative_hit_ratio']);w.writerows(rows)
lines=['# Performance and baseline comparison','', 'Cold cache per trace; all alternatives have 64 blocks of 16 bytes. Two-way and fully associative alternatives use LRU and are Python reference models, not implemented RTL. AMAT uses measured RTL hit time (2 cycles) and additional miss penalty (7 + 4L cycles). The simulation log is the source for measured latency; this script independently checks trace hit counts.', '', '| Trace | Word latency | Hits / requests | Hit % | AMAT cycles | 2-way hit % | Fully associative hit % |','|---|---:|---:|---:|---:|---:|---:|']
for name,l,n,h,m,r,a,t,f in rows: lines.append(f'| {name} | {l} | {h}/{n} | {100*r:.2f} | {a:.4f} | {100*t:.2f} | {100*f:.2f} |')
lines += ['', 'An associative model isolates placement conflicts but does not establish timing or area benefits: associativity requires additional comparators and replacement logic. Low locality can dominate capacity/conflict improvements. No-cache memory traffic baseline is one word per request; this cache reads four words per miss, so traffic is 4 × miss count. A cache can increase traffic on random/conflicting traces. A no-cache latency speed-up is not claimed because no uncached CPU adapter has been implemented.']
(out/'performance.md').write_text('\n'.join(lines)+'\n')
print('Wrote reports/performance.csv and reports/performance.md')
