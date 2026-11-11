{ config, lib, pkgs, ... }:

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  repoEditors = "${config.home.homeDirectory}/.config/anix/home/default/editors";
  machineSettings = "${config.home.homeDirectory}/.vscode-server/data/Machine/settings.json";
in
{
  # VS Code desktop on Mac reads these out-of-store symlinks. cask
  # owns app; Home Manager owns user settings.
  home.file = lib.mkIf isDarwin {
    "Library/Application Support/Code/User/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoEditors}/settings.json";
      force = true;
    };
    "Library/Application Support/Code/User/keybindings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${repoEditors}/keybindings.json";
      force = true;
    };
  };

  # The tunnel server owns and rewrites Machine settings, so merge the
  # machine-scoped keys into the existing file instead of linking it.
  home.activation.remoteVscodeSettings = lib.mkIf (!isDarwin) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${lib.escapeShellArg (dirOf machineSettings)}
      tmp="$(mktemp)"
      if [ -s ${lib.escapeShellArg machineSettings} ]; then
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
          ${lib.escapeShellArg machineSettings} ${./machine-settings.json} > "$tmp"
      else
        cp ${./machine-settings.json} "$tmp"
      fi
      install -m 644 "$tmp" ${lib.escapeShellArg machineSettings}
      rm -f "$tmp"
    ''
  );
}
