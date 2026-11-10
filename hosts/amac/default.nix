{ config, lib, pkgs, inputs, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
in
{
  imports = [
    ../../modules/common
    ../../modules/darwin
    inputs.home-manager-2605.darwinModules.home-manager
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ] ++ lib.optional (builtins.pathExists secretsFile) ./sops.nix;

  nixpkgs.hostPlatform = "x86_64-darwin";
  nixpkgs.config.allowUnfree = true;
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
    iina
    jq
    nuvio
    sops
    ssh-to-age
    ttt
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "winona" ];
  };

  nix-homebrew = {
    enable = true;
    user = "winona";
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    brews = [ "xcodes" ];
    casks = [
      "ghostty"
      "macs-fan-control"
      "stats"
    ];
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

    universalaccess = {
      reduceMotion = true;
      reduceTransparency = true;
    };

    WindowManager = {
      StandardHideWidgets = true;
      StandardHideDesktopIcons = true;
    };

    loginwindow = {
      GuestEnabled = false;
      autoLoginUser = "winona";
    };

    trackpad = {
      Clicking = true;
      Dragging = true;
      TrackpadRightClick = true;
    };
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

  # FileVault must be off for this to work. sops creates the secret after
  # activation on the first run, so a second switch applies it.
  system.activationScripts.anixAutoLogin.text = ''
    if [ -r /run/secrets/mac-login-password ]; then
      console_uid=$(/usr/bin/stat -f%u /dev/console)
      if [ "$console_uid" = "0" ]; then
        /usr/sbin/sysadminctl -autologin set -userName winona -password - \
          < /run/secrets/mac-login-password || true
      else
        /bin/launchctl asuser "$console_uid" /usr/sbin/sysadminctl \
          -autologin set -userName winona -password - \
          < /run/secrets/mac-login-password || true
      fi
    fi
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
