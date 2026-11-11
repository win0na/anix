{ lib, pkgs, ... }:

{
  xdg.enable = true;

  xdg.configFile = {
    "opencode/AGENTS.md".source = ./AGENTS.md;
    "opencode/dcp.jsonc".source = ./dcp.jsonc;
    "opencode/oh-my-opencode-slim.json".source = ./oh-my-opencode-slim.json;
    "opencode/commands/impeccable.md".source = ./commands/impeccable.md;
    "opencode/themes/catppuccin-mocha.json".source = ./themes/catppuccin-mocha.json;
    "opencode/opencode-quota/settings.jsonc".source = ./opencode-quota/settings.jsonc;
    "opencode/plugins/herdr-agent-state.js".source = ./plugins/herdr-agent-state.js;
    "opencode/plugins/rootshell-push.ts".source = ./plugins/rootshell-push.ts;
    "opencode/plugins/rtk.ts".source = ./plugins/rtk.ts;
    "opencode/plugins/opencode-dcp-fix".source = ../../../pkgs/opencode-dcp-fix;
    "opencode/oc-title-strip/tui.js".source = ./oc-title-strip/tui.js;
    "opencode/dcp-prompts".source = ./dcp-prompts;
  };

  # OpenCode rewrites these two files, so copy them instead of linking the store.
  home.activation.opencodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/opencode"
    install -m 644 ${./opencode.json} "$HOME/.config/opencode/opencode.json"
    install -m 644 ${./cli.json} "$HOME/.config/opencode/cli.json"
  '';

  home.sessionVariables = {
    OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true";
    OPENCODE_ENABLE_EXA = "1";
  };

  # uvx supplies serena and headroom; fff-mcp comes from the host overlay.
  home.packages = [ pkgs.uv ];
}
