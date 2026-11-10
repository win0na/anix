{ ... }:

{
  imports = [
    ./editors
    ./herdr
    ./opencode
    ./ttt
  ];

  home.username = "winona";
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."amac" = {
      hostname = "amac";
      user = "winona";
      identityFile = "~/.ssh/mac-builder";
    };
  };

  # TODO: shared packages, aliases, prompt.
}
