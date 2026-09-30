"""Check the tuning.conf parser in launch-game.sh without Android or the game.
Run: python tests/test_tuning.py /path/to/busybox.exe
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SHELL = str(Path(sys.argv.pop(1)).resolve())
ROOT = Path(__file__).parents[1]
LAUNCHER = (ROOT / 'installer/launch-game.sh').read_text()
PARSER = re.search(r'^# Performance settings.*?^export WINEPREFIX=[^\n]*\n', LAUNCHER, re.M | re.S).group(0)
DEFAULTS = 'TUNING FPS_CAP=60 HUD=fps,frametimes,compiler LOGS=off GPL=off ESYNC=off DRIVER=installed SHADER_CACHE=on'


class TuningTests(unittest.TestCase):
    def parse(self, content):
        with tempfile.TemporaryDirectory(prefix='thor-tuning-') as directory:
            if content is not None:
                (Path(directory) / 'tuning.conf').write_bytes(content.encode())
            script = 'print() { shift; shift; printf "%s\\n" "$*"; }\n' + PARSER + 'echo "ESYNC_ENV=$WINEESYNC"\n'
            result = subprocess.run([SHELL, 'sh', '-c', script], capture_output=True, text=True, check=True,
                                    env={'KIT': directory, 'PREFIX': '/x', 'PATH': '/usr/bin:/bin'})
            return result.stdout.splitlines()

    def test_missing_file_uses_defaults(self):
        self.assertEqual(self.parse(None), [DEFAULTS, 'ESYNC_ENV=0'])

    def test_shipped_file_matches_defaults(self):
        self.assertEqual(self.parse((ROOT / 'tuning.conf').read_text()), [DEFAULTS, 'ESYNC_ENV=0'])

    def test_all_keys_with_spaces_comments_and_crlf(self):
        out = self.parse('FPS_CAP = 90 # note\r\nHUD=off\r\nLOGS=on\nGPL=on\nESYNC=on\nDRIVER=test\nSHADER_CACHE=off')
        self.assertEqual(out, ['TUNING FPS_CAP=90 HUD=off LOGS=on GPL=on ESYNC=on DRIVER=test SHADER_CACHE=off', 'ESYNC_ENV=1'])

    def test_invalid_values_are_ignored(self):
        out = self.parse('FPS_CAP=abc\nFPS_CAP=12345\nHUD=$(reboot)\nLOGS=maybe\nDRIVER=../evil\nSHADER_CACHE=yes\nUNKNOWN=1\n')
        self.assertEqual(out, [DEFAULTS, 'ESYNC_ENV=0'])


if __name__ == '__main__':
    unittest.main()
