{ callPackage, rustPlatform, herdr-src }:

let
  upstream = callPackage (herdr-src + "/nix/package.nix") {
    inherit rustPlatform;
  };
in
upstream.overrideAttrs (old: {
  # The upstream fileset drops CHANGELOG.md and docs/next/website, which both
  # patches touch. Build from the full tag tree so the hunks apply.
  src = herdr-src;

  patches = [
    ./patches/herdr-hide-tab-bar-only.patch
    ./patches/herdr-palette-fallback.patch
  ];

  env = old.env // {
    HERDR_BUILD_CHANNEL = "rootshell";
    HERDR_BUILD_ID = "0.1.10";
    HERDR_BUILD_COMMIT = "174c20253fe07110e8b0318ce0adaa93d18a349e";
  };
})
