"""Host tests for installer/game-copies.sh: listing and removing copies of the
game in other GameHub containers. Pass a POSIX shell wrapper path as the
argument (see test_discovery.py). Temporary fixtures only. Needs
/system/bin/toybox (on a host, a wrapper that runs its arguments)."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

SHELL = sys.argv.pop(1)
INSTALLER = pathlib.Path(__file__).parents[1] / 'installer'
SOURCE = ''.join((INSTALLER / name).read_text() + '\n'
                 for name in ('discover-game.sh', 'stage-game.sh', 'game-copies.sh'))
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

    def stage(self, wow):
        game = self.usr / 'home/thor-forever/release-v1/game/_classic_beta_'
        game.mkdir(parents=True)
        (game.parent / 'Data').symlink_to(wow / 'Data')
        (game / 'Interface').symlink_to(wow / '_classic_beta_/Interface')
        return game

    def run_sh(self, body):
        script = SOURCE + body
        return subprocess.run([SHELL, 'sh'], input=script, text=True, cwd=self.root, capture_output=True)

    def scan(self, here):
        out = self.root / 'copies'
        result = self.run_sh(f'tf_scan_copies usr "usr/home/virtual_containers/{here}" copies\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        return out.read_text().splitlines() if out.exists() else None

    def remove(self, here, name, game=''):
        return self.run_sh(f'tf_remove_copy "$PWD/usr" "$PWD/usr/home/virtual_containers/{here}" '
                           f'"{name}" "{game}"\n').returncode

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

    def test_sizes(self):
        self.add_game('a')
        self.add_game('b')
        self.scan('a')
        result = self.run_sh('tf_copy_sizes usr copies sizes\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        kind, kb, name = (self.root / 'sizes').read_text().split()
        self.assertEqual((kind, name), ('SIZE', 'b'))
        self.assertGreater(int(kb), 0)

    def test_removes_other_and_relinks_staged_game(self):
        here = self.add_game('a')
        other = self.add_game('b')
        game = self.stage(other)
        self.assertEqual(self.remove('a', 'b', game), 0)
        self.assertFalse(other.exists())
        self.assertTrue((self.boxes / 'b/drive_c').is_dir())
        self.assertTrue((here / '_classic_beta_/WowB-ARM64.exe').exists())
        self.assertEqual((game.parent / 'Data').resolve(), (here / 'Data').resolve())
        self.assertEqual((game / 'Interface').resolve(), (here / '_classic_beta_/Interface').resolve())

    def test_never_removes_this_containers_copy(self):
        here = self.add_game('a')
        self.add_game('b')
        self.assertEqual(self.remove('a', 'a'), 4)
        self.assertTrue(here.exists())

    def test_refuses_without_a_copy_here(self):
        self.add_game('a')
        other = self.add_game('b')
        (self.boxes / 'c').mkdir()
        self.assertEqual(self.remove('c', 'b'), 3)
        self.assertTrue(other.exists())

    def test_refuses_odd_names(self):
        self.add_game('a')
        other = self.add_game('b')
        for name in ('', '..', '../virtual_containers/b', 'b/drive_c'):
            self.assertEqual(self.remove('a', name), 2, name)
        self.assertTrue(other.exists())

    def test_refuses_container_without_game(self):
        self.add_game('a')
        self.add_game('b')
        (self.boxes / 'c/drive_c' / PROGRAMS / 'World of Warcraft').mkdir(parents=True)
        self.assertEqual(self.remove('a', 'c'), 9)
        self.assertTrue((self.boxes / 'c/drive_c' / PROGRAMS / 'World of Warcraft').exists())

    def test_refuses_linked_container(self):
        self.add_game('a')
        other = self.add_game('b')
        (self.boxes / 'link').symlink_to(self.boxes / 'b')
        self.assertEqual(self.remove('a', 'link'), 5)
        self.assertTrue(other.exists())


if __name__ == '__main__':
    unittest.main()
