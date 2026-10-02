"""Summarize a perf.csv written by launch-game.sh with PROFILE=on.
Run: python tools/analyze-perf.py INSTALLED-WOW-<n>/perf.csv [start_s end_s]
The optional range limits the summary to seconds since the first sample,
for example the part of the session spent in a city.
"""
from collections import Counter, defaultdict
import sys

TICKS = 100  # Android's USER_HZ


def main(path, start=None, end=None):
    samples = []
    current = None
    for line in open(path, encoding='utf-8', errors='replace'):
        parts = line.rstrip('\n').split(',')
        if parts[0] == 'T' and len(parts) == 2:
            current = {'t': float(parts[1]), 'f': {}, 'g': None, 'th': {}}
            samples.append(current)
        elif current is None:
            continue
        elif parts[0] == 'f' and len(parts) == 4 and parts[2].isdigit():
            current['f'][int(parts[1])] = (int(parts[2]), int(parts[3]) if parts[3].isdigit() else None)
        elif parts[0] == 'g' and len(parts) == 3:
            current['g'] = (int(parts[1]) if parts[1].isdigit() else None,
                            int(parts[2]) if parts[2].isdigit() else None)
        elif parts[0] == 't' and len(parts) == 7:
            proc, tid, name, utime, stime, cpu = parts[1:]
            current['th'][(proc, tid)] = (name, int(utime) + int(stime), int(cpu))
    if len(samples) < 2:
        sys.exit('Not enough samples.')
    t0 = samples[0]['t']
    picked = [s for s in samples
              if (start is None or s['t'] - t0 >= start) and (end is None or s['t'] - t0 <= end)]
    if len(picked) < 2:
        sys.exit('Not enough samples in that range.')
    span = picked[-1]['t'] - picked[0]['t']
    print(f'{len(samples)} samples over {samples[-1]["t"] - t0:.0f} s; summarizing {span:.0f} s')

    usage = defaultdict(float)
    cores = defaultdict(Counter)
    names = {}
    for before, after in zip(picked, picked[1:]):
        dt = after['t'] - before['t']
        for key, (name, ticks, cpu) in after['th'].items():
            if key in before['th']:
                usage[key] += max(0, ticks - before['th'][key][1]) / TICKS
                cores[key][cpu] += 1
                names[key] = name
    print('\nBusiest threads (share of one core, most used cores):')
    for key, busy in sorted(usage.items(), key=lambda item: -item[1])[:15]:
        share = 100 * busy / span
        top = ', '.join(f'cpu{c}' for c, _ in cores[key].most_common(3))
        print(f'  {share:5.1f}%  {key[0]:<15} {names[key]:<20} {top}')
    total = 100 * sum(usage.values()) / span
    print(f'  total: {total:.0f}% of one core')

    print('\nCore clocks (average / limit, MHz):')
    per_core = defaultdict(list)
    for sample in picked:
        for core, (freq, limit) in sample['f'].items():
            per_core[core].append((freq, limit))
    for core in sorted(per_core):
        freqs = [f for f, _ in per_core[core]]
        limits = [m for _, m in per_core[core] if m]
        limit = f'{min(limits) // 1000}-{max(limits) // 1000}' if limits else '?'
        print(f'  cpu{core}: {sum(freqs) / len(freqs) / 1000:6.0f} / {limit}')

    gpu = [s['g'] for s in picked if s['g'] and s['g'][0] is not None]
    if gpu:
        busy = [b for b, _ in gpu]
        clocks = [f for _, f in gpu if f]
        clock = f', clock {sum(clocks) / len(clocks) / 1e6:.0f} MHz' if clocks else ''
        print(f'\nGPU busy: average {sum(busy) / len(busy):.0f}%, max {max(busy)}%{clock}')
    else:
        print('\nGPU busy: not readable on this device')


if __name__ == '__main__':
    if len(sys.argv) not in (2, 4):
        sys.exit(__doc__)
    main(sys.argv[1], *(float(a) for a in sys.argv[2:]))
