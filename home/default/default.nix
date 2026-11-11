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
  home.sessionVariables = lib.optionalAttrs (macUserName != null) {
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
