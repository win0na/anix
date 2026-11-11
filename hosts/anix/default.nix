{ config, lib, pkgs, inputs, userName, macUserName, ... }:

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
  nixpkgs.config.allowUnfreePredicate = p: builtins.elem (lib.getName p) [ "vscode-cli" ];
  nixpkgs.overlays = [
    inputs.rust-overlay.overlays.default
    (import ../../overlays/herdr.nix { inherit (inputs) herdr-src; })
    (import ../../overlays/default.nix)
  ];

  networking.hostName = "anix";
  system.stateVersion = "26.11";

  wsl = {
    enable = true;
    defaultUser = userName;
  };

  programs.zsh.enable = true;
  users.users.${userName}.shell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    age
    basedpyright
    curl
    fff-mcp
    git
    gopls
    herdr
    (hunspell.withDicts (dicts: [ dicts.en_US ]))
    jq
    marksman
    nil
    nixfmt
    python3
    rust-analyzer
    shellcheck
    sops
    ssh-to-age
    ttt
    typos
    typescript-language-server
    vscode-cli
    zsh
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ userName ];
    builders-use-substitutes = true;
  };

  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "amac";
      sshUser = macUserName;
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
      /home/${userName}/src amac(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000,insecure,fsid=0)
    '';
  };

  # nfs-mountd creates the export path as root when it is missing. Create it
  # first with the anix user's ownership so the project transfer can write.
  systemd.tmpfiles.rules = [
    "d /home/${userName}/src 0755 ${userName} users -"
  ];

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
    extraSpecialArgs = { inherit userName macUserName; };
    users.${userName} = {
      imports = [
        ../../home/default
        ../../home/default/anix.nix
      ];
    };
  };
}
