{ herdr-src }:
final: _prev:
let
  toolchain = final.rust-bin.fromRustupToolchainFile
    (herdr-src + "/rust-toolchain.toml");
  rustPlatform = final.makeRustPlatform {
    cargo = toolchain;
    rustc = toolchain;
  };
in
{
  herdr = final.callPackage ../pkgs/herdr {
    inherit herdr-src rustPlatform;
  };

  herdr-sidebar = final.callPackage ../pkgs/herdr-sidebar {
    inherit rustPlatform;
  };
}
