{
  lib,
  stdenv,
  rustPlatform,
  cacert,
  curl,
  fetchurl,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  p7zip,
}:

let
  # Apple ships no standalone download for the ADI libraries. These are the
  # exact builds the upstream project pins; each fetch is verified by hash and
  # nothing is downloaded at runtime.
  #
  # The macOS `adid` slice is a reference binary republished by the upstream
  # author, not an Apple download host. Replace it with a slice from a macOS
  # installer if a first-party source becomes available.
  # The host requires a POST, which fetchurl cannot resume.
  macosAdid = stdenv.mkDerivation {
    name = "CoreADI-26.x86_64";
    # Unicorn's aarch64 translation cache does 16-byte atomics, which gcc
  # lowers to libatomic calls.
  NIX_LDFLAGS = "-latomic";

  nativeBuildInputs = [ curl ];
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    buildCommand = ''
      curl --fail --location --data "" --max-filesize 3677696 \
        -o "$out" https://sharebin.eu/files/CoreADI.x86_64
    '';
    outputHashAlgo = "sha256";
    outputHashMode = "flat";
    outputHash = "sha256-S2syDwjtz11l7RFBOZt2qNkyP+4gRcV3xdLzDzWl2uE=";
  };

  # iTunes 12.13.12.3, the pinned CoreADI.dll source. The installer is 200 MB
  # and only the 1.6 MB DLL is kept.
  itunesInstaller = fetchurl {
    name = "iTunes64Setup.exe";
    url = "https://secure-appldnld.apple.com/itunes12/142-28289-20261026-6acff6c8-72eb-4045-84eb-fd35239ac645/iTunes64Setup.exe";
    hash = "sha256-IhokID9hgrfcDhgFWx6TOKDDyZLH/v5rO+BGDK8p200=";
  };

  msiSha256 = "b28e7b53865c5dc7c3fd48d707ee5c95dc2f51dd2e696a023bbb7c50a449f6f3";
  dllSha256 = "1a75abd4891fab507a6fae3ab112f42a43da0c45b9e0fec7cbef45b946c7dcae";
in
rustPlatform.buildRustPackage {
  pname = "anisette-server";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "fdkevin0";
    repo = "anisette-server-rs";
    rev = "v0.2.1";
    hash = "sha256-yBNgcVKSMolxnvWXobZW5VGlo3eE0hUMSs8TYPrw2Ew=";
  };

  cargoHash = "sha256-YCGyfEqnuDViDb37irwbLSC+11F5tKcho6V4ajCbJiY=";

  # Unicorn's aarch64 translation cache does 16-byte atomics, which gcc
  # lowers to libatomic calls.
  NIX_LDFLAGS = "-latomic";

  nativeBuildInputs = [
    cmake
    pkg-config
    p7zip
    rustPlatform.bindgenHook
  ];

  # nixpkgs forces system AWS-LC for every Rust build; this tree has no
  # system copy, so build the vendored one that ships with aws-lc-sys.
  preBuild = ''
    export AWS_LC_SYS_USE_SYSTEM=0
  '';

  # Upstream reads non-default backends from /assets, a container path. Bake in
  # this package's own share directory so the service needs no system paths.
  postPatch = ''
    substituteInPlace crates/anisette-server/src/backend.rs \
      --replace-fail '"/assets' "\"$out/share/anisette"
  '';

  # Upstream tests boot emulated guests and expect prepared assets; the server
  # is exercised through the user service and its --check mode instead.
  doCheck = false;

  postInstall = ''
    install -d $out/share/anisette

    install -m644 ${macosAdid} $out/share/anisette/CoreADI-26.x86_64

    mkdir itunes
    7z e -y -o./itunes ${itunesInstaller} iTunes64.msi > /dev/null
    echo "${msiSha256}  ./itunes/iTunes64.msi" | sha256sum -c -
    7z e -y -so ./itunes/iTunes64.msi fil69B791D2E52CAEC1073A4E4246665479 \
      > ./itunes/CoreADI.dll
    echo "${dllSha256}  ./itunes/CoreADI.dll" | sha256sum -c -
    install -m644 ./itunes/CoreADI.dll $out/share/anisette/CoreADI.dll
  '';

  meta = {
    description = "Apple ADI (anisette) service for macOS and Windows identities";
    homepage = "https://github.com/fdkevin0/anisette-server-rs";
    license = lib.licenses.gpl2Only;
    mainProgram = "anisette-server";
    platforms = lib.platforms.unix;
  };
}
