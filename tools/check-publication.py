"""Fail-closed source-only publication gate. Run before staging public files.
This is an allowlist and obvious-identifier scan, not a complete secret scanner.
Manual review and third-party license review remain required.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
allowed = {
    '.gitignore', '.gitattributes', 'README.md', 'LICENSE', 'LICENSING.md',
    'docs/SETUP.md', 'docs/TECHNICAL-NOTES.md', 'docs/TROUBLESHOOTING.md',
    'docs/RELEASE-CHECKLIST.md', 'docs/IMPLEMENTATION-STATUS.md',
    'docs/VALIDATION.md', 'docs/RECOVERY.md',
    'docs/SOURCE-PROVENANCE.md',
    'docs/BUILDING.md',
    'docs/BUNDLED-RUNTIME.md', 'tools/prepare-runtime.py',
    'docs/SOURCE-DISTRIBUTION.md', 'tools/package-sources.py',
    'tools/finalize-kit.py', 'tests/test_source_packaging.py',
    'docs/RELEASE-NOTES.md',
    'notices/LIBDRM.txt', 'notices/WAYLAND.txt',
    'notices/XKEYBOARD-CONFIG.txt', 'notices/XKBCOMMON.txt',
    'notices/BANNERS-TURNIP-GPL-3.0.txt',
    'notices/DXVK-LICENSE.txt', 'notices/WINE-LICENSE.txt', 'notices/WINE-COPYING.LIB.txt',
    'src/graphics-assert-trace.c', 'patches/dxvk-arm64-toolchain.patch',
    'src/launcher.c', 'installer/launch-game.sh', 'installer/entry.sh',
    'installer/setup.sh', 'Install-Thor-Forever.cmd', 'tools/build-launcher.ps1',
    'tools/package-candidate.ps1',
    'tests/test_release_layout.py',
    'START-HERE.md', 'patches/mesa-windows-host.patch',
    'notices/ANDROID-SHMEM-LICENSE.txt',
    'notices/ANDROID-NDK-NOTICE.txt', 'notices/MINGW-RUNTIME.txt',
    'notices/DIRECTX-HEADERS.txt', 'notices/SPIRV-HEADERS.txt',
    'notices/VULKAN-HEADERS.md', 'notices/vulkan/Apache-2.0.txt',
    'notices/vulkan/MIT.txt',
    'notices/MESA-LICENSE-OVERVIEW.rst',
    'notices/mesa/Apache-2.0', 'notices/mesa/BSL-1.0',
    'notices/mesa/GPL-1.0-or-later', 'notices/mesa/GPL-2.0-only',
    'notices/mesa/MIT', 'notices/mesa/SGI-B-2.0',
    'notices/mesa/exceptions/Linux-Syscall-Note',
    'patches/turnip-kill-local-baryf.patch', 'src/no-opengl-shim.c',
    'installer/README.md', 'installer/discover-game.sh',
    'installer/check-setup.sh', 'installer/Check-Setup.cmd',
    'installer/create-prefix.sh',
    'installer/stage-game.sh', 'tests/test_game_staging.py',
    'installer/install-report.sh', 'tests/test_install_report.py',
    'tests/test_checksum_output.py',
    'installer/Config-Thor-Forever.wtf', 'docs/DEPENDENCIES.md',
    'installer/verify-payload.sh', 'installer/install-components.sh',
    'tools/audit-runtime-archive.py', 'tests/test_archive_audit.py',
    'tests/test_discovery.py', 'tools/check-publication.py',
    'tuning.conf', 'tests/test_tuning.py',
    '.github/workflows/build-turnip.yml', '.github/workflows/build-dxvk.yml',
    'patches/dxvk-2.7-arm64-toolchain.patch', 'patches/dxvk-2.7-surface-extensions.patch',
}
problems = []
for path in root.rglob('*'):
    relative = path.relative_to(root).as_posix()
    if '.git' in path.relative_to(root).parts:
        continue
    if path.is_symlink():
        problems.append(f'Symlink: {relative}')
        continue
    if not path.is_file():
        continue
    if relative not in allowed:
        problems.append(f'Not allowlisted: {relative}')
        continue
    content = path.read_text(encoding='utf-8')
    if re.search(r'local_[0-9a-f]{8}-[0-9a-f-]{27,}', content, re.I):
        problems.append(f'Personal container identifier: {relative}')
    if re.search(r'[A-Z]:[\\/]Users[\\/][^\s/\\]+', content, re.I):
        problems.append(f'Personal Windows path: {relative}')
if problems:
    print('\n'.join(problems))
    sys.exit(1)
print('PASS: allowlisted source/documentation only; no checked personal path patterns.')
print('NOT release approval: dependency packaging and manual privacy/license review are separate checks.')
