{ lib, stdenv, fetchurl, autoPatchelfHook }:

let
  version = "1.145.2";
in
stdenv.mkDerivation {
  pname = "vscode-cli";
  inherit version;

  src = fetchurl {
    name = "vscode-cli-${version}.tar.gz";
    url = "https://update.code.visualstudio.com/${version}/cli-linux-x64/stable";
    hash = "sha256-Et/gwmvAP/iGLcQgj+8QXbUYpwJrWtZSsVjXBCRTi5A=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    tar -xzf $src -C $out/bin code
    runHook postInstall
  '';

  meta = with lib; {
    description = "Microsoft Visual Studio Code CLI and tunnel client";
    homepage = "https://code.visualstudio.com/docs/remote/tunnels";
    license = licenses.unfree;
    mainProgram = "code";
    platforms = [ "x86_64-linux" ];
  };
}
