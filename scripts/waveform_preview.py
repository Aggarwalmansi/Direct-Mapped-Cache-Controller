#!/usr/bin/env python3
"""Render actual VCD scalar transitions to a standalone SVG preview."""
from pathlib import Path
from html import escape
p=Path('build/tb_cache_top.vcd')
names=('clk','reset','cpu_req','cpu_stall','cpu_ready','blk_req','mem_word_req','mem_word_ready')
codes={}; events={n:[] for n in names}; depth=0; header=True; t=0
for line in p.open():
    s=line.split()
    if header:
        if s[:1]==['$scope']: depth+=1
        if s[:1]==['$upscope']: depth-=1
        if s[:1]==['$var'] and depth==1 and s[4] in names: codes[s[3]]=s[4]
        if s[:1]==['$enddefinitions']: header=False
    elif line.startswith('#'):
        t=int(line[1:])
        if t>1200000: break
    elif line and line[0] in '01xz' and line[1:].strip() in codes:
        events[codes[line[1:].strip()]].append((t,line[0]))
assert len(codes)==len(names), 'Missing required waveform signals'
assert all(events[n] for n in names)
W=1400; left=190; span=1180; end=1200000
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="570" viewBox="0 0 {W} 570">','<rect width="100%" height="100%" fill="white"/>','<style>text{font:15px monospace;fill:#142535}path{fill:none;stroke:#126782;stroke-width:2}</style>','<text x="20" y="30">Actual simulation waveform: first 1,200 ns (reset abort, recovery miss, hit)</text>']
for ns in range(0,1201,100):
 x=left+span*ns/1200
 svg += [f'<line x1="{x}" y1="65" x2="{x}" y2="490" stroke="#ddd"/>',f'<text x="{x-10}" y="55">{ns}</text>']
for i,n in enumerate(names):
 y=90+i*50;svg.append(f'<text x="15" y="{y+12}">{escape(n)}</text>'); pts=[];old='x'
 for t,v in events[n]+[(end,events[n][-1][1])]:
  x=left+span*t/end
  if pts:pts.append(f'L{x:.2f},{y+(0 if old=="1" else 22)}')
  pts.append(f'{"M" if not pts else "L"}{x:.2f},{y+(0 if v=="1" else 22)}');old=v
 svg.append(f'<path d="{" ".join(pts)}"/>')
svg+=['<text x="20" y="535">Time in ns; full waveform: build/tb_cache_top.vcd. Protocol/data assertions run in tb_member5.v.</text>','</svg>']
Path('reports/waveform.svg').write_text('\n'.join(svg))
print('Rendered real VCD transitions to reports/waveform.svg')
