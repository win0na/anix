{ lib, stdenv, fetchurl }:

let
  version = "1.11.0";
  base = "https://github.com/eugenioenko/ttt/releases/download/v${version}";
  src =
    if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then
      fetchurl {
        url = "${base}/ttt-darwin-arm64";
        hash = "sha256-N1FTympBZL4ZFL9sRDCnLx5g0lE1NXeQQQwzEJRvg1w=";
      }
    else if stdenv.hostPlatform.isDarwin then
      fetchurl {
        url = "${base}/ttt-darwin-amd64";
        hash = "sha256-E3L84BBXoxBLX6tHUKoFCD1uir0tWZh8vsgTkojdRQM=";
      }
    else
      fetchurl {
        url = "${base}/ttt-linux-amd64";
        hash = "sha256-w8Sjgsmbjikdg6G1J9sbQLhgfejXNz00G9Pg6SYlhYQ=";
      };
in
stdenv.mkDerivation {
  pname = "ttt";
  inherit version src;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/ttt
    chmod 755 $out/bin/ttt
  '';

  meta = with lib; {
    description = "IDE that lives in your terminal";
    homepage = "https://tttedit.dev";
    license = licenses.mit;
    mainProgram = "ttt";
    platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
