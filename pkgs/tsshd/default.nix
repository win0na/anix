# rootshell's tsshd fork: the server half of Rootshel's tssh transport.
# It carries an SSH login over UDP after a normal sshd bootstrap, so the
# control-mode auxiliary channel survives roaming.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "tsshd";
  version = "0.1.10-unstable-2026-11-22";

  src = fetchFromGitHub {
    owner = "kitknox";
    repo = "tsshd-rootshell";
    rev = "269df07a481060c23fb2ce95e513823aa1392976";
    hash = "sha256-1K1oET1kIjCU2O5WoBiYH/tWV/w8ikLirplWtGYNX30=";
  };

  vendorHash = "sha256-IesbSRd/D1oBNjuhR/7zY03KQhgJW6iBLOnyji8D7Hs=";

  subPackages = [ "cmd/tsshd" ];

  # A static binary can be copied to a system path such as /usr/local/bin
  # without pinning a store glibc that the garbage collector can remove.
  env.CGO_ENABLED = "0";

  # The suite opens live SSH sessions and UDP transports, which the build
  # sandbox does not have. Rootshel's own reconnect test is the real check.
  doCheck = false;

  meta = {
    description = "UDP SSH server with roaming, from rootshell's tsshd fork";
    homepage = "https://github.com/kitknox/tsshd-rootshell";
    license = lib.licenses.mit;
    mainProgram = "tsshd";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
