{ lib, pkgs, ... }:

{
  xdg.configFile = {
    "herdr/config.toml".source = ./config.toml;
    "herdr/catppuccin-mocha.xresources".source = ./catppuccin-mocha.xresources;
  };

  home.file.".local/bin/herdr-ide".source = ../../../scripts/herdr-ide;

  # Replace the GitHub herdr-sidebar with the single-ttt-pane build.
  home.activation.herdrSidebar = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.herdr}/bin/herdr plugin link ${pkgs.herdr-sidebar}/plugins/herdr-sidebar || true
  '';
}
