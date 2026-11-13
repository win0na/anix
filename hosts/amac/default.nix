{ config, lib, pkgs, inputs, userName, hostSystem, projectsDir, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
  projectsName = baseNameOf (lib.removeSuffix "/" projectsDir);
  mountPoint = "/Users/${userName}/${projectsName}";
  extensionLines = lib.filter
    (line: line != "" && !(lib.hasPrefix "#" line))
    (lib.splitString "\n" (builtins.readFile ../../home/default/editors/extensions.txt));
in
{
  imports = [
    ../../modules/common
    ../../modules/darwin
    inputs.home-manager-2605.darwinModules.home-manager
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ] ++ lib.optional (builtins.pathExists secretsFile) ./sops.nix;

  nixpkgs.hostPlatform = hostSystem;
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.rust-overlay.overlays.default
    (import ../../overlays/herdr.nix { inherit (inputs) herdr-src; })
    (import ../../overlays/default.nix)
  ];

  networking.hostName = "amac";
  system.stateVersion = 7;

  system.primaryUser = userName;

  # macOS gives the first account uid 501. This is not in users.knownUsers,
  # so nix-darwin does not create or delete the account; Home Manager and the
  # HM NixOS common module read the home path from here.
  users.users.${userName} = {
    uid = 501;
    home = "/Users/${userName}";
  };

  environment.systemPackages = with pkgs; [
    age
    basedpyright
    curl
    fff-mcp
    git
    gopls
    herdr
    (hunspell.withDicts (dicts: [ dicts.en_US ]))
    iina
    jq
    nil
    nixfmt
    nuvio
    python3
    rust-analyzer
    shellcheck
    sops
    ssh-to-age
    ttt
    typos
    typescript-language-server
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ userName ];
  };

  nix-homebrew = {
    enable = true;
    user = userName;
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    brews = [ "xcodes" ];
    casks = [
      "ghostty"
      "macs-fan-control"
      "stats"
      "visual-studio-code"
    ];
    vscode = extensionLines;
  };

  system.defaults = {
    dock = {
      autohide = true;
      tilesize = 40;
      mineffect = "scale";
      launchanim = false;
      show-recents = false;
      persistent-apps = [
        "/System/Library/CoreServices/Finder.app"
        "/System/Applications/Safari.app"
        "/Applications/Ghostty.app"
        "/Applications/Nix Apps/Nuvio.app"
        "/System/Applications/System Settings.app"
        "/System/Applications/Utilities/Activity Monitor.app"
      ];
    };

    finder = {
      CreateDesktop = false;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXSortFoldersFirst = true;
      AppleShowAllExtensions = true;
    };

    NSGlobalDomain = {
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
      KeyRepeat = 1;
      InitialKeyRepeat = 10;
      _HIHideMenuBar = true;
      AppleShowAllExtensions = true;
    };

    WindowManager = {
      StandardHideWidgets = true;
      StandardHideDesktopIcons = true;
    };

    loginwindow = {
      GuestEnabled = false;
      autoLoginUser = userName;
    };

    trackpad = {
      Clicking = true;
      Dragging = true;
      TrackpadRightClick = true;
    };
  };

  # Apple's OpenSSH server. Key authentication only; the builder public key is
  # installed into the primary user's authorized_keys.
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
    '';
  };

  # nix-darwin's power check rejects "restart after power failure" on Macs that
  # do not support it, which fails the whole first switch. The activation script
  # below sets autorestart with pmset instead.

  # The lid stays closed. A macOS update can reset this; activation restores it.
  # power is one of the activation script names nix-darwin actually runs.
  system.activationScripts.power.text = lib.mkAfter ''
    /usr/bin/pmset -a disablesleep 1 sleep 0 hibernatemode 0 standby 0 autopoweroff 0 womp 1 autorestart 1 ||
      echo "warning: pmset rejected one or more settings on this Mac" >&2
  '';

  # FileVault must be off for this to work. sops-nix writes the secret in
  # postActivation at priority 1500; 1600 runs after it.
  system.activationScripts.postActivation.text = lib.mkOrder 1600 ''
    if [ -s /run/secrets/mac-login-password ]; then
      console_uid=$(/usr/bin/stat -f%u /dev/console)
      if [ "$console_uid" = "0" ]; then
        /usr/sbin/sysadminctl -autologin set -userName ${lib.escapeShellArg userName} -password - \
          < /run/secrets/mac-login-password || true
      else
        /bin/launchctl asuser "$console_uid" /usr/sbin/sysadminctl \
          -autologin set -userName ${lib.escapeShellArg userName} -password - \
          < /run/secrets/mac-login-password || true
      fi
    fi
  '';

  # Retry the NFS mount every five minutes until the WSL host is reachable.
  launchd.daemons.anix-nfs = {
    command = "/Users/${userName}/.config/anix/scripts/mount-src";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 300;
      StandardOutPath = "/var/log/anix-nfs.log";
      StandardErrorPath = "/var/log/anix-nfs.log";
      EnvironmentVariables = {
        ANIX_MAC_HOME = "/Users/${userName}";
        ANIX_NFS_HOST = "anix";
        ANIX_MOUNT_POINT = mountPoint;
        ANIX_PROJECTS_DIR = projectsDir;
        ANIX_SRC_ROOT = mountPoint;
      };
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    sharedModules = [ ../../modules/home ];
    extraSpecialArgs = {
      inherit userName projectsDir;
      projectsPath = mountPoint;
      macUserName = null;
    };
    users.${userName} = {
      imports = [
        ../../home/default
        ../../home/default/amac.nix
      ];
    };
  };
}
