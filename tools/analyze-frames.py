"""Find stutters in a frames.csv written by the Thor-tuned DXVK (PROFILE=on).
Run: python tools/analyze-frames.py INSTALLED-WOW-<n>/frames.csv [start_s end_s]

A frame counts as a stutter when it takes at least twice as long as the
frames around it, and at least 25 ms longer. Each stutter gets the most
likely cause from what DXVK did in that frame or the one before it.
"""
from collections import Counter
import statistics
import sys

WINDOW = 120  # frames used for the "normal" frame time around a stutter


def main(path, start=None, end=None):
    rows = []
    with open(path, encoding='utf-8', errors='replace') as f:
        header = f.readline().strip().split(',')
        for line in f:
            parts = line.strip().split(',')
            if len(parts) != len(header):
                continue
            try:
                rows.append(dict(zip(header, map(float, parts))))
            except ValueError:
                continue
    picked = [r for r in rows
              if (start is None or r['time_ms'] / 1000 >= start)
              and (end is None or r['time_ms'] / 1000 <= end)]
    if len(picked) < WINDOW:
        sys.exit('Not enough frames.')

    times = [r['frame_ms'] for r in picked]
    span = (picked[-1]['time_ms'] - picked[0]['time_ms']) / 1000
    print(f'{len(picked)} frames over {span:.0f} s, average {len(picked) / span:.1f} FPS')
    print(f'Frame time: median {statistics.median(times):.1f} ms, '
          f'99th percentile {sorted(times)[int(len(times) * 0.99)]:.1f} ms, '
          f'worst {max(times):.1f} ms')

    stutters = []
    for i, r in enumerate(picked):
        around = times[max(0, i - WINDOW):i] or times[:WINDOW]
        normal = statistics.median(around)
        if r['frame_ms'] < max(2 * normal, normal + 25):
            continue
        before = picked[i - 1] if i else r
        extra = r['frame_ms'] - normal
        if r['new_pipelines'] or before['new_pipelines']:
            cause = 'new pipelines (shader compiling)'
        elif r['cs_wait_ms'] >= extra / 2:
            cause = 'waiting on the DXVK CS thread'
        elif r['gpu_wait_ms'] >= extra / 2:
            cause = 'waiting on the GPU'
        else:
            cause = 'none from DXVK (WoW, Wine or storage)'
        stutters.append((r, normal, cause))

    lost = sum(r['frame_ms'] - normal for r, normal, _ in stutters) / 1000
    print(f'\n{len(stutters)} stutters ({len(stutters) / span * 60:.1f} per minute), '
          f'{lost:.1f} s lost in total')
    for cause, count in Counter(c for _, _, c in stutters).most_common():
        print(f'  {count:5}  {cause}')

    print('\nWorst stutters (time, frame, normal, new pipelines, CS wait, GPU wait, cause):')
    for r, normal, cause in sorted(stutters, key=lambda s: -s[0]['frame_ms'])[:15]:
        print(f'  {r["time_ms"] / 1000:7.1f} s  {r["frame_ms"]:6.1f} ms  {normal:5.1f} ms  '
              f'{r["new_pipelines"]:3.0f}  {r["cs_wait_ms"]:6.1f} ms  {r["gpu_wait_ms"]:6.1f} ms  {cause}')

    print('\nStutters per 30 s:')
    buckets = Counter(int(r['time_ms'] / 30000) for r, _, _ in stutters)
    for b in range(int(picked[0]['time_ms'] / 30000), int(picked[-1]['time_ms'] / 30000) + 1):
        print(f'  {b * 30:5}-{b * 30 + 30:<5} s  {"#" * buckets.get(b, 0)}')


if __name__ == '__main__':
    main(sys.argv[1], *(float(a) for a in sys.argv[2:]))
