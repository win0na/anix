{ config, lib, pkgs, inputs, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
in
{
  imports = [
    ../../modules/common
    ../../modules/nixos
    inputs.nixos-wsl.nixosModules.default
    inputs.home-manager.nixosModules.home-manager
  ] ++ lib.optional (builtins.pathExists secretsFile) ./sops.nix;

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.overlays = [
    inputs.rust-overlay.overlays.default
    (import ../../overlays/herdr.nix { inherit (inputs) herdr-src; })
    (import ../../overlays/default.nix)
  ];

  networking.hostName = "anix";
  system.stateVersion = "26.11";

  wsl = {
    enable = true;
    defaultUser = "winona";
  };

  programs.zsh.enable = true;
  users.users.winona.shell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    age
    curl
    fff-mcp
    git
    herdr
    (hunspell.withDicts (dicts: [ dicts.en_US ]))
    jq
    python3
    sops
    ssh-to-age
    ttt
    typos
    zsh
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "winona" ];
    builders-use-substitutes = true;
  };

  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "amac";
      sshUser = "winona";
      sshKey = "/etc/nix/mac-builder";
      systems = [ "x86_64-darwin" ];
      protocol = "ssh-ng";
      maxJobs = 6;
      supportedFeatures = [ "big-parallel" ];
    }
  ];

  # Generate the host key for sops without running an SSH daemon.
  services.openssh = {
    enable = false;
    generateHostKeys = true;
  };

  services.nfs.server = {
    enable = true;
    createMountPoints = true;
    exports = ''
      /home/winona/src amac(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000,insecure,fsid=0)
    '';
  };

  # NFSv4 only. rpcbind and mountd still exist in the NixOS module but are
  # never opened in the firewall.
  services.nfs.settings.nfsd.vers3 = false;

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    extraInputRules = ''
      ip saddr 100.64.0.0/10 tcp dport 2049 accept
    '';
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    sharedModules = [ ../../modules/home ];
    users.winona = {
      imports = [
        ../../home/winona
        ../../home/winona/anix.nix
      ];
    };
  };
}
