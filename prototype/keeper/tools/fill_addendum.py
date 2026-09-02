#!/usr/bin/env python3
"""PROTOTYPE. Builds the addendum section of REPORT.md from results/bench-<label>.json and results/assay-2.txt for the added candidates.
Usage: python3 tools/fill_addendum.py   (edit CANDS and the labels for another batch)"""
import json, re, sys
import os
K=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R=f'{K}/results'
CANDS=['gemini37','gemini38','deepseek_max','deepseek_low','deepseek_none']
def f(v):
    if v is None: return 'n/a'
    if isinstance(v,float): return f'{v:,.1f}'
    return f'{v:,}'
def pf(b): return 'PASS' if b else '**FAIL**'
def load(label):
    with open(f'{K}/results/bench-{label}.json') as fh: return json.load(fh)
def latency(label, title):
    d=load(label); rep=d['report']
    out=[f'### Latency ({title}, n=20, item 9, cache off)','','| candidate | model (effort) | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |','|---|---|---|---|---|---|---|---|---|---|---|---|']
    for c in CANDS:
        s=rep[c]
        out.append(f"| {c} | {s['model']} | {f(s['ttft_p50'])} | {f(s['ttft_p95'])} | {f(s['total_p50'])} | {f(s['total_p95'])} | {f(s['out_tokens_mean'])} | {f(s['tps_p50'])} | {f(s['rule_ms'])} | {pf(s['pass_p50'])} | {pf(s['pass_p95'])} | {s['failures']}/{s['calls']} |")
    raw=d['raw']
    out.append(''); out.append('Warm-up (discarded): '+'; '.join(f"{c} ttft={f(raw[c]['warm'].get('ttft'))} total={f(raw[c]['warm'].get('total'))}" for c in CANDS))
    return '\n'.join(out)
def hedge(label, title):
    rep=load(label)['report']
    out=[f'### Hedging ({title}, 2 identical requests, first wins, n=20)','','| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 |','|---|---|---|---|---|---|---|']
    for c in CANDS:
        s=rep[c]; out.append(f"| {c} | {f(s['total_p95'])} | {f(s['hedged_total_p95'])} | {f(s['total_p50'])} | {f(s['hedged_total_p50'])} | {f(s['ttft_p95'])} | {f(s['hedged_ttft_p95'])} |")
    return '\n'.join(out)
def repeat(label, title):
    rep=load(label)['report']
    out=[f'### Repeat agreement ({title}, same submission ×5, cache off)','','| candidate | item 1 moon/moon | item 7 butter/spread | item 9 tide/moon | item 18 paper/scar |','|---|---|---|---|---|']
    for c in CANDS:
        cells=[]
        for rp in rep[c]['repeat']:
            vals=', '.join(str(v) for v in rp['values'])
            cells.append(f"{vals} (range {f(rp['range'])})" if rp['item']!=1 else ('100 ×5' if rp['identical'] and rp['values'] and rp['values'][0]==100 else vals))
        out.append(f"| {c} | "+' | '.join(cells)+' |')
    return '\n'.join(out)
def ordering(label, title):
    rep=load(label)['report']
    out=[f'### Ordering agreement ({title}, (A,B) vs (B,A), 20 items)','','| candidate | mean abs diff | max abs diff | within 5 | graded pairs |','|---|---|---|---|---|']
    for c in CANDS:
        o=rep[c]['ordering']; out.append(f"| {c} | {f(o['mean_abs'])} | {f(o['max_abs'])} | {f(o['within5_pct'])}% | {o['n']} |")
    return '\n'.join(out)
def assay():
    txt=open(f'{R}/assay-2.txt').read()
    table=re.search(r'(\| # \| anchors.*?)\n\ncells', txt, re.S).group(1)
    ordering=re.search(r'## Ordering agreement.*?\n\n(\| candidate.*?)\n\n==', txt, re.S).group(1)
    reasoning=re.search(r'## Reasoning \(forward ordering\)\n\n(.*?)\n## Ordering', txt, re.S).group(1)
    blocks=re.findall(r'\*\*(\d+)\. (.*?)\*\*\n((?:- .*\n)+)', reasoning)
    keep={7,9,14,18,20}
    samples=[]
    for num,title,body in blocks:
        if int(num) in keep: samples.append(f'- **{num} {title}**\n'+'\n'.join('  '+l for l in body.strip().splitlines()))
    return table, ordering, '\n'.join(samples)
def spend_line(label):
    rep=load(label)['report']; return '; '.join(f"{c} ${rep[c]['cost']:.4f}" for c in CANDS)
if __name__=='__main__':
    table, aord, samples = assay()
    add='\n\n'.join([
      '## Addendum — Gemini 3.7 / 3.8 Flash and DeepSeek V4 Flash 0731, added at Jacob\'s request',
      '''Added after the first report. `gemini-3.7-flash` and `gemini-3.8-flash` (Google, OpenAI-compatible endpoint,
`reasoning_effort: "low"`; thinking cannot be turned off and `minimal` is rejected on these two; $0.75 / $3.75 per MTok
through 2026-12-31, output priced with thoughts) and `accounts/fireworks/models/deepseek-v4-flash-0731` on Fireworks
serverless ($0.22 / $0.66 per MTok) at `reasoning_effort` **max** (Jacob's ask), **low** and **none**. Same bench, same
assay set, same evening (Mac and VPS runs about an hour after the first ones).''',
      latency('mac-2','Mac'), latency('vps-2','VPS'),
      hedge('mac-2','Mac'), hedge('vps-2','VPS'),
      repeat('mac-2','Mac'), repeat('vps-2','VPS'),
      ordering('mac-2','Mac'), ordering('vps-2','VPS'),
      '### Assay (Mac, cache off, both orderings; reconciled closeness (forward/reverse))','',
      table, '', aord, '', 'Reasoning samples (forward ordering):', '', samples,
      f"Addendum spend: Mac bench {spend_line('mac-2')}; VPS bench {spend_line('vps-2')}.",
      '<!-- ADDENDUM-READING -->'])
    p=f'{K}/REPORT.md'; s=open(p).read()
    if '## Addendum' in s: s=s[:s.index('## Addendum')].rstrip('\n')+'\n\n'
    s=s.replace('## Blind key', add+'\n\n## Blind key') if '## Blind key' in s else s+'\n\n'+add
    open(p,'w').write(s); print('addendum written')
