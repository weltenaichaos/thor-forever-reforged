#!/usr/bin/env python3
"""The installer scripts find the Thor-Forever folder from their own path."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = ['entry.sh', 'setup.sh', 'launch-game.sh', 'start-install.sh']


def kit_lines(name):
    text = (ROOT / 'installer' / name).read_text()
    assert '/sdcard/Download/Thor-Forever' not in text.replace('# ', ''), name
    return [line for line in text.splitlines() if 'KIT=' in line or line.startswith('case "$KIT"')][:2]


def main():
    shell = sys.argv[1]  # called as: shell sh -c ..., like the other tests
    lines = kit_lines(SCRIPTS[0])
    assert len(lines) == 2, lines
    for name in SCRIPTS[1:]:
        assert kit_lines(name) == lines, name
    snippet = '\n'.join(lines) + '\nprint -r -- "$KIT"\n'
    cases = {
        '/sdcard/Download/Thor-Forever/installer/entry.sh': '/sdcard/Download/Thor-Forever',
        '/storage/emulated/0/Games/Thor-Forever/installer/launch-game.sh': '/storage/emulated/0/Games/Thor-Forever',
        '/sdcard/a/installer/b/installer/setup.sh': '/sdcard/a/installer/b',
        'installer/entry.sh': None,
        '/sdcard/My Games/Thor-Forever/installer/entry.sh': None,
        '/sdcard/x/../Thor-Forever/installer/entry.sh': None,
        '/sdcard/x;rm/installer/entry.sh': None,
    }
    for zero, expected in cases.items():
        result = subprocess.run([shell, 'sh', '-c', snippet, zero], capture_output=True, text=True)
        if expected is None:
            assert result.returncode == 2 and not result.stdout, (zero, result)
        else:
            assert result.returncode == 0 and result.stdout == expected + '\n', (zero, result)
    print('OK')


if __name__ == '__main__':
    main()
