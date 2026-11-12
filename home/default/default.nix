{ config, lib, pkgs, userName, macUserName ? null, ... }:

{
  imports = [
    ./editors
    ./herdr
    ./opencode
    ./ttt
  ];

  home.username = userName;
  home.sessionPath = [ "$HOME/.local/bin" ];
  home.sessionVariables = {
    # The sops CLI on macOS looks under ~/Library by default; both hosts use
    # the same key path so an edit works from either one.
    SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  } // lib.optionalAttrs (macUserName != null) {
    ANIX_MAC_USER = macUserName;
    ANIX_MAC_HOME = "/Users/${macUserName}";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = lib.optionalAttrs (macUserName != null) {
      amac = {
        hostname = "amac";
        user = macUserName;
        identityFile = "~/.ssh/mac-builder";
      };
    };
  };

  # TODO: shared packages, aliases, prompt.
}
