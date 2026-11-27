{ lib, pkgs, ... }:

{
  xdg.configFile = {
    "herdr/config.toml".source = ./config.toml;
    "herdr/catppuccin-mocha.xresources".source = ./catppuccin-mocha.xresources;
  };

  home.file.".local/bin/herdr-ide".source = ../../../scripts/herdr-ide;
  home.file.".local/bin/herdr-action".source = ../../../scripts/herdr-action;

  # Replace the GitHub herdr-sidebar with the single-ttt-pane build.
  home.activation.herdrSidebar = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -z "''${DRY_RUN:-}" ]; then
      if ! ${pkgs.herdr}/bin/herdr plugin link ${pkgs.herdr-sidebar}/plugins/herdr-sidebar; then
        echo "anix: herdr sidebar link failed; run: herdr plugin link" >&2
      fi
    fi
  '';
}
