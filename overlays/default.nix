final: prev:

{
  fff-mcp = final.callPackage ../pkgs/fff-mcp { };
  ttt = final.callPackage ../pkgs/ttt { };
}
// prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  brew-shim = final.callPackage ../pkgs/brew-shim { };
  nuvio = final.callPackage ../pkgs/nuvio { };
}
// prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
  anisette-server = final.callPackage ../pkgs/anisette-server { };
  vscode-cli = final.callPackage ../pkgs/vscode-cli { };
}
