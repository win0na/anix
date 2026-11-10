{ ... }:

# Verified build facts for kitknox/herdr rootshell-v0.1.10:
#
# - rustPlatform.buildRustPackage
# - src = herdr-src (the flake input)
# - cargoLock.lockFile = "${herdr-src}/Cargo.lock"
# - Zig dependencies from vendor/libghostty-vt/build.zig.zon.nix
# - nativeBuildInputs: zig_0_16, zstd, pkg-config, git
# - Darwin build inputs: cctools, xcbuild
# - doCheck = false
# - HERDR_BUILD_CHANNEL=rootshell
# - HERDR_BUILD_ID=0.1.10
# - two patches in ./patches: herdr-hide-tab-bar-only.patch,
#   herdr-palette-fallback.patch
#
# TODO: write the derivation. The Darwin build has never run in upstream CI.
{
}
