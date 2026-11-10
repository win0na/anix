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
  # - services.openssh.enable = true; services.openssh.openFirewall = false
  #   services.openssh.listenAddresses = [ { addr = "127.0.0.1"; port = 22; } ]
  #   (local sshd generates the host key used by sops)
  # - nix.settings.trusted-users
  # - NFS export of ~/src for amac
  # - remote builder registration
  # - sops-nix secrets
  # - system.stateVersion
}
