{ config, lib, pkgs, inputs, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
in
{
  imports = [
    ../../modules/common
    ../../modules/darwin
    inputs.home-manager-2605.darwinModules.home-manager
  ] ++ lib.optional (builtins.pathExists secretsFile) ./sops.nix;

  nixpkgs.hostPlatform = "x86_64-darwin";
  nixpkgs.overlays = [
    inputs.rust-overlay.overlays.default
    (import ../../overlays/herdr.nix { inherit (inputs) herdr-src; })
    (import ../../overlays/default.nix)
  ];

  networking.hostName = "amac";
  system.stateVersion = 7;

  system.primaryUser = "winona";

  # Not in users.knownUsers, so nix-darwin does not create or delete the
  # account. The values let Home Manager read the existing home directory.
  users.users.winona = {
    uid = 501;
    home = "/Users/winona";
  };

  environment.systemPackages = with pkgs; [
    age
    curl
    fff-mcp
    git
    herdr
    jq
    sops
    ssh-to-age
    ttt
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "winona" ];
  };

  # Apple's OpenSSH server. Key authentication only; the builder public key is
  # installed into winona's authorized_keys.
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
    '';
  };

  power.restartAfterPowerFailure = true;

  # The lid stays closed. A macOS update can reset this; activation restores it.
  system.activationScripts.anixPower.text = ''
    /usr/bin/pmset -a disablesleep 1 sleep 0 hibernatemode 0 standby 0 autopoweroff 0 womp 1 autorestart 1
  '';

  # Retry the NFS mount every five minutes until the WSL host is reachable.
  launchd.daemons.anix-nfs = {
    command = "/Users/winona/.config/anix/scripts/mount-src";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 300;
      StandardOutPath = "/var/log/anix-nfs.log";
      StandardErrorPath = "/var/log/anix-nfs.log";
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    sharedModules = [ ../../modules/home ];
    users.winona = {
      imports = [
        ../../home/winona
        ../../home/winona/amac.nix
      ];
    };
  };
}
