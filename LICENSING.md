# Licensing scope

The MIT license in `LICENSE` applies to Thor Forever's original installer scripts,
original utility code, tests and documentation. The project's attribution uses
the owner's public GitHub handle, AeroNico. Thor Forever Reforged is a fork;
changes made in the fork are also MIT, under the additional copyright line in
`LICENSE`.

It does not relicense Wine, Mesa/Turnip, DXVK, GameHub, Blizzard software,
third-party code or their assets. Changes to and excerpts from upstream source
must be distributed in accordance with that upstream component's applicable
license and notices. In particular, do not interpret the root MIT license as
relicensing the Mesa source context included in `patches/`.

No game files or personal prefixes are included. The Git tree contains source
and notices; the experimental release separately provides a runtime kit and
source companion. See `docs/SOURCE-DISTRIBUTION.md` for source archives, patches,
build information and license scope. A checksum alone does not fulfill source
or notice obligations. Preserve applicable notices when redistributing.

The scoped no-OpenGL shim in `src/` is original utility code, not a copy of
Mesa's OpenGL implementation. Its inclusion does not grant rights to distribute
unrelated OpenGL libraries.
