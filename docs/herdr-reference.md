# Herdr reference

Pins and settings for the Herdr stack. Values are fixed at the versions below.
Change a pin in the same commit as the config that uses it.

## Core

| Item | Value |
| --- | --- |
| Source | `github:kitknox/herdr` |
| Tag | `rootshell-v0.1.10` |
| Commit | `174c202` |
| Build channel | `HERDR_BUILD_CHANNEL=rootshell` |
| Build id | `HERDR_BUILD_ID=0.1.10` |
| Installed version | `herdr 0.9.5-rootshell.0.1.10` |
| Patch 1 | `herdr-hide-tab-bar-only.patch` |
| Patch 2 | `herdr-palette-fallback.patch` |

## Plugins

| Id | Version | Source | Commit |
| --- | --- | --- | --- |
| `responsive-sidebar` | 0.1.0 | First-party, Nix-packaged | Local |
| `herdr-bar` | 0.14.0 | `jeffarese/herdr-bar` | `d9cdd88cb734615e96b1c37ed17fc39be904f060` |
| `herdr-sidebar` | 0.15.1 | `alexarthurs/herdr-sidebar`, subdir `plugins/herdr-sidebar` | `081ed133f3faa377438b51ce435fe8a87c439593` |
| `ttt.editor` | 0.1.2 | `eugenioenko/ttt`, subdir `herdr-plugin` | `b51ae983e0f60599090e0b0061093dbece9b541f` |

The `herdr-sidebar` pin receives the editor-pane patch. The patch is not shipped
in this skeleton.

## ttt

| Item | Value |
| --- | --- |
| Binary version | 1.11.0 |
| Theme | `catppuccin-mocha` |
| Reuse window | `true` |
| Focus on open | `true` |
| Format on save | `true` |
| Sidebar | Hidden |
| Socket directory | `$TMPDIR/ttt-uid/` |
| Forward override | `TTT_FORWARD_SOCKET` |

`reuseWindow` forwards an open request to the newest socket in the socket
directory and exits. The layout gives each workspace its own `TMPDIR` so the
newest socket belongs to that workspace.

## LSP servers

| Language | Command |
| --- | --- |
| Rust | `rust-analyzer` |
| TypeScript, JavaScript | `typescript-language-server --stdio` |
| Go | `gopls` |
| Swift | `sourcekit-lsp` |
| Nix | `nil` |
| Python | `basedpyright-langserver --stdio` |
| Markdown | `marksman server` |

ttt configures LSP with a server command and a language list. It does not
accept per-server `initializationOptions`, settings, or environment variables.

## Herdr actions

| Action | Id |
| --- | --- |
| Open sidebar | `plugin.herdr-sidebar.open-sidebar` |
| Open Source Control | `plugin.herdr-sidebar.open-git` |
| Show Explorer | `plugin.herdr-sidebar.show-explorer` |
| Show Search | `plugin.herdr-sidebar.show-search` |
| Show Source Control | `plugin.herdr-sidebar.show-git` |
| Quick open | `plugin.herdr-sidebar.quick-open` |
| Refresh sidebars | `plugin.herdr-sidebar.refresh-sidebars` |
| Toggle responsive sidebar | `plugin.responsive-sidebar.toggle` |
| Open status bar | `plugin.herdr-bar.open` |

## Layout

| Part | Value |
| --- | --- |
| Sidebar | Left pane, Explorer and Source Control toggle in place |
| Center | Agent or terminal |
| ttt | Bottom split, 35 percent |
| ttt per workspace | One |
| Tab bar | Hidden |
| Palette | Catppuccin mocha, loaded from `~/.config/herdr/catppuccin-mocha.xresources` |
| Docked sidebar threshold | 110 columns |

## Directories

| Variable | Purpose |
| --- | --- |
| `HERDR_PLUGIN_CONFIG_DIR` | Plugin configuration |
| `HERDR_PLUGIN_STATE_DIR` | Plugin state |
| `~/.config/herdr/config.toml` | Herdr config and keybindings |
| `~/.config/herdr/plugins.json` | Installed plugin registry |
