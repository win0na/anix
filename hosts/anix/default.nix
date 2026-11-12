{ config, lib, pkgs, inputs, userName, macUserName, projectsDir, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
  projectsPath =
    if builtins.substring 0 1 projectsDir == "/" then projectsDir
    else "/home/${userName}/${projectsDir}";
  projectsDirs =
    let
      homePrefix = "/home/${userName}";
      absolute = builtins.substring 0 1 projectsDir == "/";
      inHome = absolute && lib.hasPrefix "${homePrefix}/" projectsDir;
      relative = if absolute then lib.removePrefix "${homePrefix}/" projectsDir else projectsDir;
      parts = lib.splitString "/" relative;
    in
    if absolute && !inHome then
      [ ]
    else
      lib.genList
        (i: "${homePrefix}/" + lib.concatStringsSep "/" (lib.take (i + 1) parts))
        (builtins.length parts);
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
      # The Mac serves its own architecture. An Intel Mac cannot build
      # aarch64, and an Apple silicon Mac builds x86_64 only under Rosetta.
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
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
    createMountPoints = false;
    exports = ''
      ${projectsPath} amac(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000,insecure,fsid=0)
    '';
  };

  # Create the project root and every relative parent with the anix user's
  # ownership. An absolute root must already exist; this never chowns a system
  # path. nfs-mountd is not allowed to create the export path as root.
  systemd.tmpfiles.rules = map
    (dir: "d ${dir} 0755 ${userName} users -")
    projectsDirs;

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
    extraSpecialArgs = { inherit userName macUserName projectsDir projectsPath; };
    users.${userName} = {
      imports = [
        ../../home/default
        ../../home/default/anix.nix
      ];
    };
  };
}
