{ ... }:

{
  imports = [
    ../../modules/common
    ../../modules/darwin
  ];

  nixpkgs.hostPlatform = "x86_64-darwin";
  networking.hostName = "amac";

  # TODO (configuration pass):
  # - system.primaryUser = "winona"
  # - users.users.winona.home = "/Users/winona"
  # - nix-homebrew wiring
  # - sops-nix secrets
  # - power settings and auto-login activation
  # - NFS mount of ~/src from anix
  # - system.stateVersion = 7
}
