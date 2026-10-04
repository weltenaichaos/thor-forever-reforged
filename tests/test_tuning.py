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
SWAP = re.search(r'^tf_sha256\(\)\n.*?^}\n', LAUNCHER, re.M | re.S).group(0) + re.search(
    r'^# DXVK=test puts.*?^if \[ "\$tf_dxvk" = installed \].*?^fi\n', LAUNCHER, re.M | re.S).group(0)
WINE_SWAP = re.search(r'^tf_sha256\(\)\n.*?^}\n', LAUNCHER, re.M | re.S).group(0) + re.search(
    r'^# WINE=test swaps in.*?^print -r -- "WINE_NTDLL_DLL_SHA256=\$tf_hash"\n', LAUNCHER, re.M | re.S).group(0)
ENTRY_CLEANUP = re.search(r'^# Each launch leaves ENTRY.*?^esac\n', LAUNCHER, re.M | re.S).group(0)
DEFAULTS = 'TUNING FPS_CAP=60 HUD=fps,frametimes,compiler LOGS=off GPL=off ESYNC=off DRIVER=installed SHADER_CACHE=on DXVK=installed DXVK_TILER=auto PROFILE=off AFFINITY=all TURNIP_MODE=auto WINE=installed'
SHIPPED = 'TUNING FPS_CAP=60 HUD=fps,frametimes,compiler LOGS=off GPL=off ESYNC=on DRIVER=test SHADER_CACHE=on DXVK=test DXVK_TILER=off PROFILE=off AFFINITY=all TURNIP_MODE=auto WINE=installed'


class TuningTests(unittest.TestCase):
    def parse(self, content, path='/usr/bin:/bin', test_files=False):
        with tempfile.TemporaryDirectory(prefix='thor-tuning-') as directory:
            if content is not None:
                (Path(directory) / 'tuning.conf').write_bytes(content.encode())
            if test_files:
                for name in ('driver-test/libvulkan_freedreno.so', 'dxvk-test/dxgi.dll', 'dxvk-test/d3d11.dll', 'wine-test/ntdll.so'):
                    (Path(directory) / name).parent.mkdir(exist_ok=True)
                    (Path(directory) / name).write_text('x')
            script = 'print() { shift; shift; echo "$*"; }\n' + PARSER + 'echo "ESYNC_ENV=$WINEESYNC"\n'
            result = subprocess.run([SHELL, 'sh', '-c', script], capture_output=True, text=True, check=True,
                                    env={'KIT': directory, 'PREFIX': '/x', 'PATH': path})
            return result.stdout.splitlines()

    def test_missing_file_uses_defaults(self):
        self.assertEqual(self.parse(None), [DEFAULTS, 'ESYNC_ENV=0'])

    def test_shipped_file_is_the_best_tested_setup(self):
        self.assertEqual(self.parse((ROOT / 'tuning.conf').read_text(), test_files=True), [SHIPPED, 'ESYNC_ENV=1'])

    def test_shipped_file_without_test_files_falls_back_safely(self):
        self.assertEqual(self.parse((ROOT / 'tuning.conf').read_text()), [
            SHIPPED,
            'DRIVER=test, but driver-test/libvulkan_freedreno.so is missing: using the installed driver.',
            'DXVK=test, but dxvk-test/dxgi.dll is missing: using the installed DXVK.',
            'ESYNC=on only works with DRIVER=test: esync stays off.',
            'ESYNC_ENV=0'])

    def test_esync_needs_the_test_driver(self):
        out = self.parse('ESYNC=on\nDRIVER=installed\n', test_files=True)
        self.assertEqual(out[1:], ['ESYNC=on only works with DRIVER=test: esync stays off.', 'ESYNC_ENV=0'])

    def test_all_keys_with_spaces_comments_and_crlf(self):
        out = self.parse('FPS_CAP = 90 # note\r\nHUD=off\r\nLOGS=on\nGPL=on\nESYNC=on\nDRIVER=test\nSHADER_CACHE=off\nDXVK=test\nDXVK_TILER=off\nPROFILE=on\nAFFINITY=big\nTURNIP_MODE=gmem\nWINE=test', test_files=True)
        self.assertEqual(out, ['TUNING FPS_CAP=90 HUD=off LOGS=on GPL=on ESYNC=on DRIVER=test SHADER_CACHE=off DXVK=test DXVK_TILER=off PROFILE=on AFFINITY=big TURNIP_MODE=gmem WINE=test', 'ESYNC_ENV=1'])

    def test_logs_trace(self):
        self.assertEqual(self.parse('LOGS=trace\n')[0], DEFAULTS.replace('LOGS=off', 'LOGS=trace'))

    def test_parser_runs_no_external_commands(self):
        # On device, GameHub prefixes every external command's output with its
        # own text, which corrupted values; the parser must be shell-only.
        out = self.parse((ROOT / 'tuning.conf').read_text(), path='/nonexistent', test_files=True)
        self.assertEqual(out, [SHIPPED, 'ESYNC_ENV=1'])

    def test_invalid_values_are_ignored(self):
        out = self.parse('FPS_CAP=abc\nFPS_CAP=12345\nHUD=$(reboot)\nLOGS=maybe\nDRIVER=../evil\nSHADER_CACHE=yes\nDXVK=latest\nDXVK_TILER=maybe\nPROFILE=yes\nAFFINITY=f8\nTURNIP_MODE=fast\nWINE=latest\nUNKNOWN=1\n')
        self.assertEqual(out, [DEFAULTS, 'ESYNC_ENV=0'])


class DxvkSwapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='thor-dxvk-')
        base = Path(self.tmp.name)
        self.kit, self.root = base / 'kit', base / 'root'
        self.sys32 = self.root / 'prefix/drive_c/windows/system32'
        for folder in (self.kit / 'payload', self.kit / 'dxvk-test', self.sys32):
            folder.mkdir(parents=True)
        for dll in ('dxgi.dll', 'd3d11.dll'):
            (self.kit / 'payload' / dll).write_text('installed ' + dll)
            (self.kit / 'dxvk-test' / dll).write_text('test ' + dll)
            (self.sys32 / dll).write_text('installed ' + dll)

    def tearDown(self):
        self.tmp.cleanup()

    def swap(self, mode):
        script = ('print() { shift; shift; echo "$*"; }\nfail() { echo "STOP: $1"; exit 12; }\n'
                  f'tf_dxvk={mode}\n' + SWAP + 'echo DONE\n')
        return subprocess.run([SHELL, 'sh', '-c', script], capture_output=True, text=True, env={
            'KIT': str(self.kit), 'ROOT': str(self.root), 'PREFIX': str(self.root / 'prefix'), 'PATH': '/usr/bin:/bin'})

    def contents(self):
        return [(self.sys32 / dll).read_text() for dll in ('dxgi.dll', 'd3d11.dll')]

    def test_test_then_installed_round_trip(self):
        self.assertIn('DONE', self.swap('test').stdout)
        self.assertEqual(self.contents(), ['test dxgi.dll', 'test d3d11.dll'])
        self.assertTrue((self.root / 'dxvk-test-active').exists())
        self.assertIn('DONE', self.swap('installed').stdout)
        self.assertEqual(self.contents(), ['installed dxgi.dll', 'installed d3d11.dll'])
        self.assertFalse((self.root / 'dxvk-test-active').exists())

    def test_missing_test_dll_changes_nothing(self):
        (self.kit / 'dxvk-test/d3d11.dll').unlink()
        result = self.swap('test')
        self.assertEqual(result.returncode, 12)
        self.assertIn('dxvk-test/d3d11.dll is missing', result.stdout)
        self.assertEqual(self.contents(), ['installed dxgi.dll', 'installed d3d11.dll'])
        self.assertFalse((self.root / 'dxvk-test-active').exists())



class WineSwapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='thor-wine-')
        base = Path(self.tmp.name)
        self.kit, self.root = base / 'kit', base / 'root'
        self.unix = self.root / 'runtime/lib/wine/aarch64-unix'
        self.pe = self.root / 'runtime/lib/wine/aarch64-windows'
        self.sys = self.root / 'prefix/drive_c/windows/system32'
        for folder in (self.kit / 'wine-test', self.unix, self.pe, self.sys):
            folder.mkdir(parents=True)
        (self.kit / 'wine-test/ntdll.so').write_text('test ntdll')
        (self.unix / 'ntdll.so').write_text('installed ntdll')
        for folder in (self.pe, self.sys):
            (folder / 'ntdll.dll').write_text('installed dll')

    def tearDown(self):
        self.tmp.cleanup()

    def swap(self, mode):
        script = ('print() { shift; shift; echo "$*"; }\nfail() { echo "STOP: $1"; exit 12; }\n'
                  f'tf_wine={mode}\n' + WINE_SWAP + 'echo DONE\n')
        return subprocess.run([SHELL, 'sh', '-c', script], capture_output=True, text=True, env={
            'KIT': str(self.kit), 'ROOT': str(self.root), 'RUNTIME': str(self.root / 'runtime'),
            'PREFIX': str(self.root / 'prefix'), 'PATH': '/usr/bin:/bin'})

    def files(self):
        return [(folder / name).read_text() for folder, name in
                ((self.unix, 'ntdll.so'), (self.pe, 'ntdll.dll'), (self.sys, 'ntdll.dll'))]

    def leftovers(self):
        return sorted(path.name for path in self.root.rglob('*') if path.name.endswith(('.installed', '.tmp'))) + \
            (['wine-test-active'] if (self.root / 'wine-test-active').exists() else [])

    def test_test_then_installed_round_trip(self):
        self.assertIn('DONE', self.swap('test').stdout)
        self.assertEqual(self.files(), ['test ntdll', 'installed dll', 'installed dll'])
        self.assertIn('DONE', self.swap('test').stdout)
        self.assertIn('DONE', self.swap('installed').stdout)
        self.assertEqual(self.files(), ['installed ntdll', 'installed dll', 'installed dll'])
        self.assertEqual(self.leftovers(), [])

    def test_matching_dll_is_swapped_in_both_places_and_back(self):
        (self.kit / 'wine-test/ntdll.dll').write_text('test dll')
        self.assertIn('DONE', self.swap('test').stdout)
        self.assertEqual(self.files(), ['test ntdll', 'test dll', 'test dll'])
        (self.kit / 'wine-test/ntdll.dll').unlink()
        self.assertIn('DONE', self.swap('test').stdout)
        self.assertEqual(self.files(), ['test ntdll', 'installed dll', 'installed dll'])
        (self.kit / 'wine-test/ntdll.dll').write_text('test dll')
        self.assertIn('DONE', self.swap('test').stdout)
        self.assertIn('DONE', self.swap('installed').stdout)
        self.assertEqual(self.files(), ['installed ntdll', 'installed dll', 'installed dll'])
        self.assertEqual(self.leftovers(), [])

    def test_installed_without_swap_changes_nothing(self):
        self.assertIn('DONE', self.swap('installed').stdout)
        self.assertEqual(self.files(), ['installed ntdll', 'installed dll', 'installed dll'])
        self.assertEqual(self.leftovers(), [])

    def test_mismatched_prefix_dll_stops(self):
        (self.sys / 'ntdll.dll').write_text('other dll')
        out = self.swap('installed').stdout
        self.assertIn('STOP: The runtime and prefix ntdll.dll differ.', out)


class EntryCleanupTests(unittest.TestCase):
    NAMES = ['ENTRY-1-5.log', 'ENTRY-1-5.started', 'ENTRY-1-5.done', 'ENTRY-2-7.log', 'ENTRY-2-7.started',
             'ENTRY-3-9.tmp', 'ENTRY-4-1.log', 'ENTRY-4-1.started', 'tuning.conf', 'ENTRY-notes.txt']

    def run_cleanup(self, token):
        with tempfile.TemporaryDirectory(prefix='thor-entry-') as directory:
            for name in self.NAMES:
                (Path(directory) / name).write_text('x')
            env = {'KIT': directory, 'PATH': '/usr/bin:/bin'}
            if token is not None:
                env['TF_ENTRY_TOKEN'] = token
            subprocess.run([SHELL, 'sh', '-c', ENTRY_CLEANUP], check=True, env=env)
            return sorted(path.name for path in Path(directory).iterdir())

    def test_keeps_only_this_launch_and_unrelated_files(self):
        self.assertEqual(self.run_cleanup('4-1'), ['ENTRY-3-9.tmp', 'ENTRY-4-1.log', 'ENTRY-4-1.started',
                                                   'ENTRY-notes.txt', 'tuning.conf'])

    def test_without_a_valid_token_nothing_is_removed(self):
        for token in (None, '', '../x', '*'):
            self.assertEqual(self.run_cleanup(token), sorted(self.NAMES))


if __name__ == '__main__':
    unittest.main()
