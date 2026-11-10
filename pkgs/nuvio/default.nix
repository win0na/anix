{ lib, stdenvNoCC, fetchurl, undmg }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nuvio";
  version = "0.1.35-alpha";

  src = fetchurl {
    url = "https://github.com/NuvioMedia/NuvioDesktop/releases/download/${finalAttrs.version}/Nuvio-macOS-x86_64-${finalAttrs.version}.dmg";
    hash = "sha256-bmUrrKlL9xgak9Jf7pd5QMw1DJJSGBmInwsCQ0HNhR4=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = "Nuvio.app";

  installPhase = ''
    mkdir -p $out/Applications
    cp -R . $out/Applications/Nuvio.app
  '';

  meta = with lib; {
    description = "Nuvio desktop media client";
    homepage = "https://github.com/NuvioMedia/NuvioDesktop";
    license = licenses.unfree;
    platforms = [ "x86_64-darwin" ];
  };
})
