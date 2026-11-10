{ config, lib, pkgs, ... }:

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  repoEditors = "${config.home.homeDirectory}/.config/anix/home/winona/editors";
  csUser = "${config.xdg.dataHome}/code-server/User";
in
{
  # VS Code desktop on the Mac reads these out-of-store symlinks. The cask
  # owns the app; Home Manager owns the user settings.
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

  # code-server rewrites its user files, so copy the canonical settings in
  # instead of linking them.
  home.activation.codeServerSettings = lib.mkIf (!isDarwin) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${lib.escapeShellArg csUser}
      tmp="$(mktemp)"
      if [ -s ${lib.escapeShellArg "${csUser}/settings.json"} ]; then
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
          ${lib.escapeShellArg "${csUser}/settings.json"} ${./settings.json} > "$tmp"
      else
        cp ${./settings.json} "$tmp"
      fi
      install -m 644 "$tmp" ${lib.escapeShellArg "${csUser}/settings.json"}
      rm -f "$tmp"
      install -m 644 ${./keybindings.json} ${lib.escapeShellArg "${csUser}/keybindings.json"}
    ''
  );

  home.activation.codeServerExtensions = lib.mkIf (!isDarwin) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x ${pkgs.code-server}/bin/code-server ]; then
        while IFS= read -r ext; do
          case "$ext" in
            ""|\#*) continue ;;
          esac
          ${pkgs.code-server}/bin/code-server \
            --user-data-dir "$HOME/.local/share/code-server" \
            --install-extension "$ext" --force >/dev/null 2>&1 \
            || echo "code-server: failed to install $ext" >&2
        done < ${./extensions.txt}
      fi
    ''
  );
}
