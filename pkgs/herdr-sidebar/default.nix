{ lib, stdenv, fetchurl, rustPlatform }:

let
  rev = "081ed133f3faa377438b51ce435fe8a87c439593";
  version = "0.15.1";
in
rustPlatform.buildRustPackage {
  pname = "herdr-sidebar";
  inherit version;

  src = fetchurl {
    url = "https://github.com/alexarthurs/herdr-sidebar/archive/${rev}.tar.gz";
    hash = "sha256-/4AgomKYuBmVhUqIYSC9wrxqmEIfv4tUXzRyP7jh/PQ=";
  };

  sourceRoot = "herdr-sidebar-${rev}/plugins/herdr-sidebar";

  cargoLock.lockFile = ./Cargo.lock;

  patches = [ ../herdr-sidebar-patch/herdr-sidebar-ttt.patch ];

  doCheck = false;

  postInstall = ''
    mkdir -p $out/plugins/herdr-sidebar/target/release
    mkdir -p $out/plugins/herdr-sidebar/scripts

    cp herdr-plugin.toml $out/plugins/herdr-sidebar/
    cp $out/bin/herdr-sidebar $out/plugins/herdr-sidebar/target/release/
    cp $out/bin/herdr-sidebar-ensure $out/plugins/herdr-sidebar/target/release/

    # The manifest still declares a build command. The binary is already here.
    cat > $out/plugins/herdr-sidebar/scripts/fetch-or-build.sh <<'EOF'
    #!/bin/sh
    test -x "$(dirname "$0")/../target/release/herdr-sidebar"
    EOF
    chmod 755 $out/plugins/herdr-sidebar/scripts/fetch-or-build.sh
  '';

  meta = with lib; {
    description = "VS Code-style sidebar for Herdr, with a single ttt editor pane";
    homepage = "https://github.com/alexarthurs/herdr-sidebar";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "x86_64-darwin" ];
  };
}
