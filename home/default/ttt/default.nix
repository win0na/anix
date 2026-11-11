{ lib, ... }:

{
  xdg.configFile."ttt/plugins".source = ./plugins;

  home.file.".local/bin/ttt-handoff" = {
    source = ../../../scripts/ttt-handoff;
    executable = true;
  };

  # ttt rewrites these when settings or plugins change.
  home.activation.tttConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/ttt"
    install -m 644 ${./settings.json} "$HOME/.config/ttt/settings.json"
    install -m 644 ${./plugins.ttt.json} "$HOME/.config/ttt/plugins.ttt.json"
  '';
}
