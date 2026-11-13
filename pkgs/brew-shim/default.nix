{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "brew-shim";
  version = "0.1.0";

  src = lib.cleanSource ./.;  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "Homebrew-compatible brew command backed by MacPorts";
    license = licenses.mit;
    mainProgram = "brew";
    platforms = [
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
