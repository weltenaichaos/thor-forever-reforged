#!/bin/sh
# Links one DXVK DLL as ARM64X: one file that holds native ARM64 code (for
# WoW's ARM64 client) and ARM64EC code (for x64 programs such as Battle.net,
# which Wine runs through an emulator).
#
# Usage: link-arm64x.sh NATIVE_BUILD EC_BUILD TARGET OUTPUT
#   NATIVE_BUILD  Meson build directory configured for aarch64
#   EC_BUILD      Meson build directory configured for arm64ec
#   TARGET        ninja target, for example src/d3d11/d3d11.dll
#   OUTPUT        absolute path of the ARM64X DLL to write
#
# It takes the native build's own link command and changes three things:
# the arm64ec driver with -marm64x links both halves, the EC build's
# objects and static libraries are added to the same link, and the import
# library is dropped (nothing links against it). The EC build's resource
# file is left out, because the native one already carries the version info.
set -eu

native=$1
ec=$2
target=$3
output=$4

native_cmd=$(ninja -C "$native" -t commands "$target" | tail -n 1)
ec_cmd=$(ninja -C "$ec" -t commands "$target" | tail -n 1)
ec_rel=$(realpath --relative-to="$native" "$ec")

ec_inputs=$(printf '%s\n' "$ec_cmd" | tr ' ' '\n' \
  | grep -E '\.(obj|a)$' | grep -v -e '^-' -e 'version\.o' \
  | sed "s#^#$ec_rel/#" | tr '\n' ' ')

case "$native_cmd" in
  *aarch64-w64-mingw32-clang++*) ;;
  *) echo "unexpected link command: $native_cmd" >&2; exit 1 ;;
esac

link_cmd=$(printf '%s\n' "$native_cmd" | sed \
  -e 's#aarch64-w64-mingw32-clang++#arm64ec-w64-mingw32-clang++ -marm64x#' \
  -e "s#-o $target #-o $output #" \
  -e 's#-Wl,--out-implib=[^ ]*##' \
  -e "s#-Wl,--end-group#$ec_inputs -Wl,--end-group#")

cd "$native"
eval "$link_cmd"
