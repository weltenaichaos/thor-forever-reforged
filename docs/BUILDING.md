# Developer build notes

These are build inputs for the tested components, not beginner installation
instructions and not a claim of bit-for-bit reproducibility. New binaries need
hash updates and device acceptance; do not silently substitute them into a
previously verified payload set.

## Windows ARM64 entry

Use llvm-mingw 20260922 UCRT's `aarch64-w64-mingw32-clang.exe`:

```powershell
./tools/build-launcher.ps1 -Compiler <compiler-path> -OutputFile <new-output-path>
```

The script uses `-O2 -Wall -Wextra -Werror -municode -mwindows` and links
`user32`. The final device-tested RC2 launcher SHA-256 is
`311918c59c089352853035caa8abf5984fe37c41378bc2472aff1407161ccd79`.

## Wine

Use revision `52796bf615c265c23b22ae9dacc3da9e38c8487f` of the owner's
proton-wine fork, including directaudio at
`2101085596ffe4911f7686012a97585eacbde9d0`. The matching GitHub workflow is
`.github/workflows/build-proton-11.0-1.yml`; it calls `build-scripts/`.
Preserve that revision's Android patch application, runtime dependency handling,
NDK r27d, ARM64/API-28 target and 16 KiB page option. The workflow uses bylaws'
LLVM MinGW 20250920 for Wine; do not confuse that with the newer DXVK toolchain.

The source tar does not populate Git submodules. The workflow also downloads
external Termux/runtime components. See SOURCE-PROVENANCE.md for why the Wine
commit alone is not a complete inventory of everything in the resulting tar.

## Android shared-memory library

Use `android/android_sysvshm` from the pinned Wine source. The tested standalone
build used NDK r27d clang, `--target=aarch64-linux-android28`, its matching
sysroot, and:

```text
-Wall -std=gnu99 -shared -fPIC -O2 -g0
-Wl,-z,max-page-size=16384 -Wl,-soname,libandroid-sysvshm.so -Wl,--no-undefined
```

Add that source directory to the include path and compile `android_sysvshm.c`.
Check source and output hashes against DEPENDENCIES.md.

## DXVK

Use 2.4.1 at `0cf05780abd7250c2cd713b7749cf32180157cf5` and apply
`patches/dxvk-arm64-toolchain.patch`. Preserve these Git submodule revisions:

| Directory | Revision |
| --- | --- |
| include/native/directx | `9df86f2341616ef1888ae59919feaa6d4fad693d` |
| include/spirv | `8b246ff75c6615ba4532fe4fde20f1be090c3764` |
| include/vulkan | `46dc0f6e514f5730784bb2cac2a7c731636839e8` |
| subprojects/libdisplay-info | `275e6459c7ab1ddd4b125f28d0440716e4888078` |

The historical cross-file uses llvm-mingw 20260922 UCRT's aarch64 compiler,
archiver, strip, windres and widl tools, with glslang 16.6.0. Set Meson's host
machine to Windows/aarch64/little-endian and `cpp_args = ['-include', 'algorithm']`.
Use native Windows ARM64 DLL outputs, not x64 or ARM64EC substitutions.

`.github/workflows/build-dxvk.yml` rebuilds this baseline and DXVK 2.7.1 on
GitHub Actions. 2.7.1 needs `patches/dxvk-2.7-arm64-toolchain.patch`, the same
libc++ fix at its new location. Test a build on the device with `DXVK=test`
in `tuning.conf`.

## Patched Turnip

Start from Mesa `fe067b17d908d8f02e88ef3c4433ec5fbb66b2a9`. Apply both
`patches/mesa-windows-host.patch` and `patches/turnip-kill-local-baryf.patch`.
The source archive SHA-256 is
`6eb6aebf2701f863185a28fe4ffa0cb5cfb3c78a266caa530352149a29d3b382`.

The historical Windows host used NDK r27d clang/clang++ with
`--target=aarch64-linux-android28`; Meson's host machine is Android/aarch64,
little-endian. Use `needs_exe_wrapper = true`, `c_link_args = ['-lz']` and
`cpp_link_args = ['-static-libstdc++', '-lz']`. Native build tools are
llvm-mingw x86_64, Python, glslang 16.6.0 and winflexbison. Configure:

```text
--wrap-mode=nofallback
-Dgallium-drivers= -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl
-Dplatforms=android -Dandroid-stub=true -Dandroid-libbacktrace=disabled
-Dandroid-libperfetto=disabled -Dplatform-sdk-version=28
-Dglx=disabled -Degl=disabled -Dgbm=disabled -Dllvm=disabled
-Dgles1=disabled -Dgles2=disabled -Dopengl=false -Dbuild-tests=false
-Dvideo-codecs= -Dbuildtype=release -Dzlib=disabled -Dzstd=disabled
-Dexpat=disabled -Dshader-cache=disabled
```

Use tool paths supplied by the developer, never a copied personal absolute path.
This is the separately patched game driver, not the additional Wayland variants
bundled in the Wine tar. Their build recipes and source revisions are different.

## Scoped diagnostic helpers

Both helper sources compile with NDK r27d's clang targeting Android ARM64/API 28:

```text
clang --target=aarch64-linux-android28 -shared -fPIC -O2 -Wl,-z,max-page-size=16384 -Wl,-soname,libGL.so.1 src/no-opengl-shim.c -o libGL.so.1
clang --target=aarch64-linux-android28 -shared -fPIC -O2 -Wl,-z,max-page-size=16384 src/graphics-assert-trace.c -ldl -o trace.so
```

On PowerShell, quote each comma-containing `-Wl,...` argument. These commands
were compile-checked on the packaging host. They do not reproduce the historical
payload hashes; the release retains the original device-tested helpers. Any new
helper build needs its own validation. Do not substitute it silently.

## Packaging

First run `python -B tools/prepare-runtime.py ORIGINAL.tar NEW-OUTPUT.tar`.
It accepts only the tested original runtime hash and excludes exactly
`prefixPack.txz` and `profile.json`. Thor Forever never imports that upstream
prefix; it creates a fresh one with `create-prefix.sh`. All 2,589 retained
members are compared against the original for content and metadata equality.
Use the resulting archive as `payload/wine-runtime.tar`. This is a packaging
change, not a rebuild or replacement of Wine libraries. See BUNDLED-RUNTIME.md.

`tools/package-candidate.ps1` verifies the seven input hashes and copies only
the selected installation material into a new directory. It refuses overwrites
and normalizes shell/CMD line endings. Its output is explicitly a **private
candidate**, not permission to publish binary dependencies with incomplete
notices/source materials. It never reads the handheld's game, prefix or account
directories and does not upload anything.

After source/notice review, `python -B tools/finalize-kit.py STAGED-KIT NEW.zip`
checks every candidate file, all seven payloads and the exact tested launcher.
It creates a ZIP with per-file checksums and verifies ZIP integrity. Source
companion packaging is described in SOURCE-DISTRIBUTION.md. These tools never
publish a release automatically.
