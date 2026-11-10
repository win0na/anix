{ ... }:

{
  imports = [
    ../../modules/common
    ../../modules/nixos
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "anix";

  # TODO (configuration pass):
  # - wsl.enable = true
  # - wsl.defaultUser = "winona"
  # - nix.settings.trusted-users
  # - NFS export of ~/src for amac
  # - remote builder registration
  # - sops-nix secrets
  # - system.stateVersion
}
