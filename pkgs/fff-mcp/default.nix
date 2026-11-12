{ lib, stdenv, fetchurl }:

let
  version = "0.11.0";
  base = "https://github.com/dmtrKovalenko/fff/releases/download/v${version}";
  src =
    if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then
      fetchurl {
        url = "${base}/fff-mcp-aarch64-apple-darwin";
        hash = "sha256-zGBtlBjPp3ZDdtzXsyoz5kWabLmkcYvjZrAk3Kbp/q0=";
      }
    else if stdenv.hostPlatform.isDarwin then
      fetchurl {
        url = "${base}/fff-mcp-x86_64-apple-darwin";
        hash = "sha256-Mzd6j5ZELryLBtO9KGPPZqUg+XozcA4PuFoJ3XmI6GI=";
      }
    else
      fetchurl {
        url = "${base}/fff-mcp-x86_64-unknown-linux-musl";
        hash = "sha256-0ehnH0DInERaqhcooh7AS3S+Ll+ZCRSFyuq8yX+ZrOs=";
      };
in
stdenv.mkDerivation {
  pname = "fff-mcp";
  inherit version src;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/fff-mcp
    chmod 755 $out/bin/fff-mcp
  '';

  meta = with lib; {
    description = "MCP server for fff, a fast file search tool";
    homepage = "https://github.com/dmtrKovalenko/fff";
    license = licenses.mit;
    mainProgram = "fff-mcp";
    platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
