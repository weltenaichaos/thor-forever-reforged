"""Host tests for installer/install-state.sh, which tells the start screen
whether to offer Play, Install or Repair. Pass a POSIX shell wrapper path as
the argument (see test_discovery.py). Temporary fixtures only."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

SHELL = sys.argv.pop(1)
INSTALLER = pathlib.Path(__file__).parents[1] / 'installer'
SOURCE = ''.join((INSTALLER / name).read_text() + '\n' for name in ('discover-game.sh', 'install-state.sh'))
PAYLOAD = ['wine-runtime.tar', 'd3d11.dll', 'dxgi.dll', 'libandroid-sysvshm.so',
           'libvulkan_freedreno.so', 'libGL.so.1', 'trace.so']


class InstallStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='thor-state-')
        self.root = pathlib.Path(self.temp.name)
        self.usr = self.root / 'usr'
        self.kit = self.root / 'kit'
        (self.kit / 'payload').mkdir(parents=True)
        for name in PAYLOAD:
            (self.kit / 'payload' / name).write_bytes(b'x')
        game = self.usr / 'home/virtual_containers/a/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_'
        game.mkdir(parents=True)
        (game / 'WowB-ARM64.exe').write_bytes(b'fixture')

    def tearDown(self):
        self.temp.cleanup()

    def install(self, complete=True):
        root = self.usr / 'home/thor-forever/release-v1'
        (root / 'prefix').mkdir(parents=True)
        (root / 'game/_classic_beta_').mkdir(parents=True)
        (root / 'components-ready').write_text('COMPONENTS_READY')
        (root / 'prefix/system.reg').write_text('reg')
        (root / 'game/_classic_beta_/WowB-ARM64.exe').write_bytes(b'fixture')
        if complete:
            (root / 'game-ready').write_text('GAME_STAGED')
        return root

    def state(self, container='a'):
        script = SOURCE + f'tf_install_state "$PWD/usr" "$PWD/usr/home/virtual_containers/{container}" "$PWD/kit"\n'
        result = subprocess.run([SHELL, 'sh'], input=script, text=True, cwd=self.root, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_not_installed(self):
        self.assertEqual(self.state(), ['STATE missing', 'GAME found', 'PAYLOAD ok', 'OLD 0'])

    def test_installed(self):
        self.install()
        self.assertEqual(self.state()[0], 'STATE installed')

    def test_unfinished_is_broken(self):
        self.install(complete=False)
        self.assertEqual(self.state()[0], 'STATE broken')

    def test_game_missing_here(self):
        (self.usr / 'home/virtual_containers/b').mkdir()
        self.assertEqual(self.state('b')[1], 'GAME found')  # the only copy is used, as before
        other = self.usr / 'home/virtual_containers/c/drive_c/Program Files/World of Warcraft/_classic_beta_'
        other.mkdir(parents=True)
        (other / 'WowB-ARM64.exe').write_bytes(b'fixture')
        self.assertEqual(self.state('b')[1], 'GAME multiple')

    def test_payload_missing(self):
        (self.kit / 'payload/trace.so').unlink()
        (self.kit / 'payload/dxgi.dll').write_bytes(b'')
        self.assertEqual(self.state()[2], 'PAYLOAD missing dxgi.dll trace.so')

    def test_old_installations_counted(self):
        self.install()
        (self.usr / 'home/thor-forever/release-v1.old-1').mkdir()
        self.assertEqual(self.state()[3], 'OLD 1')


if __name__ == '__main__':
    unittest.main()
