{ lib, pkgs, ... }:

{
  xdg.enable = true;

  xdg.configFile = {
    "opencode/AGENTS.md".source = ./AGENTS.md;
    "opencode/dcp.jsonc".source = ./dcp.jsonc;
    "opencode/commands/impeccable.md".source = ./commands/impeccable.md;
    "opencode/themes/catppuccin-mocha.json".source = ./themes/catppuccin-mocha.json;
    "opencode/plugins/herdr-agent-state.js".source = ./plugins/herdr-agent-state.js;
    "opencode/plugins/rootshell-push.ts".source = ./plugins/rootshell-push.ts;
    "opencode/plugins/rtk.ts".source = ./plugins/rtk.ts;
    "opencode/dcp-fix".source = ../../../pkgs/opencode-dcp-fix;
    "opencode/oc-title-strip/tui.js".source = ./oc-title-strip/tui.js;
    "opencode/dcp-prompts".source = ./dcp-prompts;
  };

  # OpenCode and its plugins rewrite these files, so keep writable copies. A
  # changed destination is backed up before the switch installs the new one.
  home.activation.opencodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -z "''${DRY_RUN:-}" ]; then
      install_config() {
        local src=$1 dst=$2 backup_dir backup
        if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
          backup_dir="$HOME/.local/state/anix/opencode-backups"
          mkdir -p "$backup_dir"
          backup="$backup_dir/$(basename "$dst").$(date +%Y%m%d%H%M%S).$$"
          cp -p "$dst" "$backup"
          echo "anix: backed up $dst to $backup"
        fi
        install -m 644 "$src" "$dst"
      }
      mkdir -p "$HOME/.config/opencode/opencode-quota"
      install_config ${./opencode.json} "$HOME/.config/opencode/opencode.json"
      install_config ${./cli.json} "$HOME/.config/opencode/cli.json"
      install_config ${./oh-my-opencode-slim.json} "$HOME/.config/opencode/oh-my-opencode-slim.json"
      install_config ${./opencode-quota/settings.jsonc} "$HOME/.config/opencode/opencode-quota/settings.jsonc"
      find "$HOME/.config/opencode/logs/dcp" -type f -mtime +7 -delete 2>/dev/null || true
      find "$HOME/.config/opencode/logs/dcp" -type d -empty -delete 2>/dev/null || true
    fi
  '';

  home.sessionVariables = {
    OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true";
    OPENCODE_ENABLE_EXA = "1";
  };

  # uvx supplies serena and headroom; fff-mcp comes from the host overlay.
  home.packages = [ pkgs.uv ];
}
