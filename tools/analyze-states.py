"""Summarize state.csv (WoW's main thread every 50 ms, PROFILE=on).
Run: python tools/analyze-states.py logs/run-<n>/state.csv [start_s end_s]

R = running, S = sleeping (waiting for another thread, a timer or I/O),
D = waiting on the disk. A stall is a stretch of 100 ms or more in which
the main thread did not run; during a stall the game cannot draw a frame.
The kernel function it waited in (wchan) hints at what it waited for.
R also covers "ready but waiting for a free core"; the schedstat columns
(newer launchers) show how much of that there was.
"""
from collections import Counter, defaultdict
import sys


def main(path, start=None, end=None):
    samples = []
    for line in open(path, encoding='utf-8', errors='replace'):
        parts = line.strip().split(',')
        if len(parts) not in (3, 5):
            continue
        try:
            sched = (int(parts[3]), int(parts[4])) if len(parts) == 5 and parts[3] and parts[4] else None
            samples.append((float(parts[0]), parts[1], parts[2] or '?', sched))
        except ValueError:
            continue
    if len(samples) < 2:
        sys.exit('Not enough samples.')
    t0 = samples[0][0]
    picked = [s for s in samples
              if (start is None or s[0] - t0 >= start) and (end is None or s[0] - t0 <= end)]
    span = picked[-1][0] - picked[0][0]
    print(f'{len(picked)} samples over {span:.0f} s ({len(picked) / max(span, 1):.0f} per second)')

    states = Counter(s for _, s, _, _ in picked)
    print('\nMain thread state:')
    for state, count in states.most_common():
        print(f'  {state}  {100 * count / len(picked):5.1f}%')

    waits = Counter(w for _, s, w, _ in picked if s != 'R')
    print('\nWhere it waited (share of all samples):')
    for wchan, count in waits.most_common(8):
        print(f'  {100 * count / len(picked):5.1f}%  {wchan}')

    stalls = []
    run = []
    for sample in picked + [(None, 'R', '', None)]:
        if sample[1] != 'R':
            run.append(sample)
            continue
        if run and (sample[0] or run[-1][0]) - run[0][0] >= 0.1:
            length = (sample[0] or run[-1][0]) - run[0][0]
            wchan = Counter(w for _, _, w, _ in run).most_common(1)[0][0]
            stalls.append((run[0][0] - t0, length, wchan, Counter(s for _, s, _, _ in run).most_common(1)[0][0]))
        run = []

    print(f'\n{len(stalls)} stalls of 100 ms or more ({len(stalls) / max(span, 1) * 60:.1f} per minute), '
          f'{sum(l for _, l, _, _ in stalls):.1f} s in total')
    by_wchan = defaultdict(list)
    for stall in stalls:
        by_wchan[(stall[3], stall[2])].append(stall[1])
    for (state, wchan), lengths in sorted(by_wchan.items(), key=lambda kv: -sum(kv[1])):
        print(f'  {len(lengths):4}  {sum(lengths):5.1f} s  {state} {wchan}')
    print('\nLongest stalls (time, length, state, waited in):')
    for t, length, wchan, state in sorted(stalls, key=lambda s: -s[1])[:12]:
        print(f'  {t:7.1f} s  {length * 1000:5.0f} ms  {state}  {wchan}')

    # schedstat: time on a core and time ready to run but waiting for a core.
    sched = [(t, x) for t, _, _, x in picked if x]
    if len(sched) >= 2:
        (t_a, (run_a, rq_a)), (t_b, (run_b, rq_b)) = sched[0], sched[-1]
        wall = (t_b - t_a) * 1e9
        print(f'\nOn a core {100 * (run_b - run_a) / wall:.1f}% of the time, '
              f'waiting for a free core {100 * (rq_b - rq_a) / wall:.1f}%')
        starved = []
        for (t1, (r1, q1)), (t2, (r2, q2)) in zip(sched, sched[1:]):
            if t2 > t1 and (q2 - q1) / ((t2 - t1) * 1e9) >= 0.5:
                starved.append((t1 - t0, (q2 - q1) / 1e6))
        print(f'{len(starved)} samples where it waited for a core more than half the time'
              f' ({len(starved) / max(span, 1) * 60:.1f} per minute)')
        for t, ms in sorted(starved, key=lambda s: -s[1])[:8]:
            print(f'  {t:7.1f} s  {ms:5.0f} ms waiting for a core')


if __name__ == '__main__':
    main(sys.argv[1], *(float(a) for a in sys.argv[2:]))
