"""Host tests for installer/game-copies.sh: listing copies of the game in
other GameHub containers. Pass a POSIX shell wrapper path as the argument
(see test_discovery.py). Temporary fixtures only."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

SHELL = sys.argv.pop(1)
INSTALLER = pathlib.Path(__file__).parents[1] / 'installer'
SOURCE = ''.join((INSTALLER / name).read_text() + '\n'
                 for name in ('discover-game.sh', 'game-copies.sh'))
PROGRAMS = 'Program Files (x86)'


class GameCopiesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='thor-copies-')
        self.root = pathlib.Path(self.temp.name)
        self.usr = self.root / 'usr'
        self.boxes = self.usr / 'home/virtual_containers'
        self.boxes.mkdir(parents=True)

    def tearDown(self):
        self.temp.cleanup()

    def add_game(self, container):
        wow = self.boxes / container / 'drive_c' / PROGRAMS / 'World of Warcraft'
        (wow / '_classic_beta_/Interface/AddOns').mkdir(parents=True)
        (wow / '_classic_beta_/WowB-ARM64.exe').write_bytes(b'fixture-not-a-real-game')
        (wow / 'Data').mkdir()
        (wow / 'Data/fixture').write_text('x' * 5000)
        return wow

    def run_sh(self, body):
        script = SOURCE + body
        return subprocess.run([SHELL, 'sh'], input=script, text=True, cwd=self.root, capture_output=True)

    def scan(self, here):
        out = self.root / 'copies'
        result = self.run_sh(f'tf_scan_copies usr "usr/home/virtual_containers/{here}" copies\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        return out.read_text().splitlines() if out.exists() else None

    def test_one_copy_writes_nothing(self):
        self.add_game('a')
        self.assertIsNone(self.scan('a'))

    def test_lists_here_and_other(self):
        self.add_game('a')
        self.add_game('b')
        self.assertEqual(sorted(self.scan('a')), ['HERE a', 'OTHER b'])

    def test_lists_elsewhere_without_a_copy_here(self):
        self.add_game('a')
        self.add_game('b')
        (self.boxes / 'c').mkdir()
        self.assertEqual(sorted(self.scan('c')), ['ELSEWHERE a', 'ELSEWHERE b'])

    def test_lists_leftovers(self):
        # A copy whose removal stopped halfway: no WowB-ARM64.exe any more.
        self.add_game('a')
        other = self.add_game('b')
        (other / '_classic_beta_/WowB-ARM64.exe').unlink()
        self.assertEqual(self.scan('a'), ['LEFTOVER b'])

    def test_leftovers_only_listed_with_a_copy_here(self):
        other = self.add_game('b')
        (other / '_classic_beta_/WowB-ARM64.exe').unlink()
        self.add_game('a')
        (self.boxes / 'c').mkdir()
        self.assertIsNone(self.scan('c'))


if __name__ == '__main__':
    unittest.main()
