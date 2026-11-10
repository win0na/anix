final: prev:

{
  fff-mcp = final.callPackage ../pkgs/fff-mcp { };
  ttt = final.callPackage ../pkgs/ttt { };
}
// prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  nuvio = final.callPackage ../pkgs/nuvio { };
}
