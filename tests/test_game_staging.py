"""Temporary fixtures only. Pass a Windows busybox.exe path as the argument."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

SHELL = str(Path(sys.argv.pop(1)).resolve())
SOURCE = (Path(__file__).parents[1] / 'installer/stage-game.sh').read_text()


class StagingTests(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory(prefix='thor-stage-') as directory:
            root = Path(directory)
            game = root / 'original/World of Warcraft/_classic_beta_'
            game.mkdir(parents=True)
            (game / 'WowB-ARM64.exe').write_bytes(b'fixture-executable')
            (game / 'WTF').mkdir()
            (game / 'WTF/Account.txt').write_text('private-fixture')
            (game / 'WTF/Config.wtf').write_text('original-settings')
            install = root / 'dedicated'
            install.mkdir()
            (install / 'components-ready').write_text('COMPONENTS_READY')
            (root / 'starter.wtf').write_text('starter-settings')
            if mode != 'missing-data':
                data = game / 'Data' if mode == 'child-data' else game.parent / 'Data'
                data.mkdir()
                (data / 'fixture').write_text('shared-data')
            if mode == 'existing':
                (install / 'game').mkdir()
                (install / 'game/keep').write_text('do-not-touch')
            # Host portability shim only; Android uses mksh's print builtin.
            script = 'print() { shift; shift; printf "%s\\n" "$*"; }\n' + SOURCE
            script += '\ntf_stage_game "$1" "$2" "$3"\n'
            result = subprocess.run(
                [SHELL, 'sh', '-c', script, 'test', game.as_posix(),
                 install.as_posix(), (root / 'starter.wtf').as_posix()],
                capture_output=True, text=True)
            if mode in ('missing-data', 'existing'):
                self.assertEqual(result.returncode, 55 if mode == 'missing-data' else 54, result.stderr)
                self.assertFalse((install / 'game-ready').exists())
                if mode == 'existing':
                    self.assertEqual((install / 'game/keep').read_text(), 'do-not-touch')
            else:
                if result.returncode == 60 and sys.platform == 'win32' and 'Permission denied' in result.stderr:
                    self.assertFalse((install / 'game-ready').exists())
                    self.assertEqual((game / 'WTF/Config.wtf').read_text(), 'original-settings')
                    self.skipTest('Windows denied directory symlink creation; Android validation required')
                self.assertEqual(result.returncode, 0, result.stderr)
                staged = install / 'game/_classic_beta_'
                self.assertEqual((staged / 'WowB-ARM64.exe').read_bytes(), b'fixture-executable')
                self.assertFalse((staged / 'WTF/Account.txt').exists())
                self.assertEqual((staged / 'WTF/Config-Thor-Forever.wtf').read_text(), 'starter-settings')
                link = staged / 'Data' if mode == 'child-data' else install / 'game/Data'
                self.assertTrue(link.is_symlink())
                self.assertEqual((link / 'fixture').read_text(), 'shared-data')
                interface = staged / 'Interface'
                self.assertTrue(interface.is_symlink())
                self.assertEqual(Path(os.readlink(interface)), game / 'Interface')
                self.assertTrue((game / 'Interface/AddOns').is_dir())
            self.assertEqual((game / 'WTF/Config.wtf').read_text(), 'original-settings')

    def link(self, source, game):
        script = SOURCE + '\ntf_link_interface "$1" "$2"\n'
        return subprocess.run([SHELL, 'sh', '-c', script, 'test', source.as_posix(), game.as_posix()],
                              capture_output=True, text=True).returncode

    def test_link_existing_install(self):
        with tempfile.TemporaryDirectory(prefix='thor-link-') as directory:
            root = Path(directory)
            source, game = root / 'original/_classic_beta_', root / 'staged/_classic_beta_'
            source.mkdir(parents=True)
            game.mkdir(parents=True)
            self.assertEqual(self.link(source, game), 0)
            self.assertTrue((game / 'Interface').is_symlink())
            (source / 'Interface/AddOns/MyAddon').mkdir()
            self.assertTrue((game / 'Interface/AddOns/MyAddon').is_dir())
            self.assertEqual(self.link(source, game), 0)  # every launch: already linked

    def test_link_existing_addons_kept(self):
        with tempfile.TemporaryDirectory(prefix='thor-link-') as directory:
            root = Path(directory)
            source, game = root / 'original/_classic_beta_', root / 'staged/_classic_beta_'
            (source / 'Interface/AddOns/Mine').mkdir(parents=True)
            game.mkdir(parents=True)
            self.assertEqual(self.link(source, game), 0)
            self.assertTrue((game / 'Interface/AddOns/Mine').is_dir())

    def test_link_leaves_real_folder(self):
        with tempfile.TemporaryDirectory(prefix='thor-link-') as directory:
            root = Path(directory)
            source, game = root / 'original/_classic_beta_', root / 'staged/_classic_beta_'
            source.mkdir(parents=True)
            (game / 'Interface/AddOns/Keep').mkdir(parents=True)
            self.assertEqual(self.link(source, game), 72)
            self.assertFalse((game / 'Interface').is_symlink())
            self.assertTrue((game / 'Interface/AddOns/Keep').is_dir())

    def test_link_replaces_empty_folder(self):
        with tempfile.TemporaryDirectory(prefix='thor-link-') as directory:
            root = Path(directory)
            source, game = root / 'original/_classic_beta_', root / 'staged/_classic_beta_'
            (source / 'Interface/AddOns/Mine').mkdir(parents=True)
            (game / 'Interface/AddOns').mkdir(parents=True)
            self.assertEqual(self.link(source, game), 0)
            self.assertTrue((game / 'Interface').is_symlink())
            self.assertTrue((game / 'Interface/AddOns/Mine').is_dir())

    def test_link_refuses_foreign_link(self):
        with tempfile.TemporaryDirectory(prefix='thor-link-') as directory:
            root = Path(directory)
            source, game = root / 'original/_classic_beta_', root / 'staged/_classic_beta_'
            source.mkdir(parents=True)
            game.mkdir(parents=True)
            (root / 'elsewhere').mkdir()
            os.symlink(root / 'elsewhere', game / 'Interface')
            self.assertEqual(self.link(source, game), 71)
            self.assertEqual(Path(os.readlink(game / 'Interface')), root / 'elsewhere')

    def sync(self, src, dest):
        script = 'print() { shift; shift; printf "%s\\n" "$*"; }\n' + SOURCE + '\ntf_sync_addons "$1" "$2"\n'
        return subprocess.run([SHELL, 'sh', '-c', script, 'test', src.as_posix(), dest.as_posix()],
                              capture_output=True, text=True)

    def test_sync_addons(self):
        with tempfile.TemporaryDirectory(prefix='thor-sync-') as directory:
            root = Path(directory)
            src, dest = root / 'kit/AddOns', root / 'game/Interface/AddOns'
            (src / 'New').mkdir(parents=True)
            (src / 'New/New.toc').write_text('v2')
            (src / 'NoToc').mkdir()
            (dest / 'New').mkdir(parents=True)
            (dest / 'New/old.lua').write_text('stale')
            (dest / 'Other').mkdir()
            (dest / 'Other/Other.toc').write_text('keep')
            result = self.sync(src, dest)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('ADDON COPIED: New', result.stdout)
            self.assertIn('ADDON SKIPPED: NoToc', result.stdout)
            self.assertEqual((dest / 'New/New.toc').read_text(), 'v2')
            self.assertFalse((dest / 'New/old.lua').exists())
            self.assertFalse((dest / 'NoToc').exists())
            self.assertEqual((dest / 'Other/Other.toc').read_text(), 'keep')
            self.assertEqual([p.name for p in dest.iterdir() if p.name.startswith('.')], [])

    def test_sync_without_folder(self):
        with tempfile.TemporaryDirectory(prefix='thor-sync-') as directory:
            root = Path(directory)
            result = self.sync(root / 'missing', root / 'dest')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / 'dest').exists())

    def test_parent_data(self): self.run_case('parent-data')
    def test_child_data(self): self.run_case('child-data')
    def test_existing_refused(self): self.run_case('existing')
    def test_missing_data(self): self.run_case('missing-data')


if __name__ == '__main__':
    unittest.main()
