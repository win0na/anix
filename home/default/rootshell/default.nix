{ config, ... }:

let
  bin = "${config.home.homeDirectory}/.local/bin";
in
{
  home.file = {
    ".local/bin/xdg-open" = {
      source = ./xdg-open;
      executable = true;
    };
    ".local/bin/rootshell-open" = {
      source = ./rootshell-open;
      executable = true;
    };
    ".local/bin/rootshell-open-clipboard" = {
      source = ./rootshell-open-clipboard;
      executable = true;
    };
  };

  # Tools that spawn a browser through $BROWSER reach the same wrapper.
  home.sessionVariables.BROWSER = "${bin}/xdg-open";
}
