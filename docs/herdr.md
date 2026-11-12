# Editor stack

Herdr manages panes and workspaces. ttt is the editor. A patched sidebar
connects them. OpenCode runs the agents in the center pane.

## Layout

```text
+----------------------+----------------------------------+
| Explorer             | Agent or terminal                |
| Source Control       |                                  |
+----------------------+----------------------------------+
| ttt, one pane per workspace                             |
+---------------------------------------------------------+
```

`prefix+i` runs `herdr-ide`: it splits the focused pane, starts ttt with a
workspace `TMPDIR`, records `hs-ttt-workspace` and `hs-ttt-tmpdir` on the pane,
opens the sidebar, and focuses the agent again. The Herdr tab bar is hidden.

## Pieces

| Piece | Role |
| --- | --- |
| `pkgs/herdr` | Herdr 0.9.5 from the rootshell fork, with two patches. |
| `pkgs/herdr-sidebar` | `alexarthurs/herdr-sidebar` at `081ed13`, with two patches. |
| `pkgs/herdr-plugins` | First-party `responsive-sidebar` plugin. |
| `pkgs/ttt` | ttt 1.11.0 release binary. |
| `pkgs/fff-mcp` | fff MCP server for OpenCode. |

The core patches hide the tab bar on its own and add a palette fallback. The
sidebar patches replace per-file editor tabs with one ttt pane, and add **Open
in VS Code** to the file context menu. The second one calls `ttt-handoff`, which
opens the file on amac through the code tunnel.

Home Manager links the patched sidebar build. Do not install
`alexarthurs/herdr-sidebar` from GitHub on top of it; that replaces the patched
copy with the stock plugin.

## Keys

| Key | Action |
| --- | --- |
| `prefix+i` | IDE layout: sidebar, agent, ttt |
| `prefix+e` | Open ttt in the focused pane |
| `prefix+s` | Toggle the responsive sidebar |
| `prefix+k` | Open the command bar |

## ttt

`home/default/ttt/settings.json` sets Catppuccin mocha, `reuseWindow`, icons
off, 4-space indents, and `focusOnOpen` and `formatOnSave` off. It has no
`lsp.servers` list. ttt accepts a server command plus a language list, and no
per-server settings, so add entries when a project needs LSP.

`reuseWindow` forwards an open request to the newest socket under
`$TMPDIR/ttt-uid/` and exits. The per-workspace `TMPDIR` is what keeps that
socket inside the current workspace.

## Opening a file

The explorer runs `ttt <file>` detached and then focuses the ttt pane. Because
ttt reuses the newest socket for that workspace, the file appears in the pane
that is already open instead of a new tab.

## OpenCode

One configuration is shared by both hosts. Provider credentials are interactive
OAuth logins stored in OpenCode's local state, not in sops. The MCP servers are
`fff`, `headroom`, and `serena`.

`pkgs/opencode-dcp-fix` is vendored and loaded as a local plugin. It strips
three kinds of internal metadata from prompts and replies: system reminders,
DCP nudges, and `@N@` / `@bN@` references. Its tests run with `node --test`.

The plugin list also includes `oh-my-opencode-slim`, the DCP plugin, the
Anthropic auth plugin, and the quota plugin. `service.json` and `auth.json` are
local state; they stay out of the repository.

## What stays manual

Plugin pins live in `flake.nix`. Update a pin, rebuild, and run
`herdr plugin list`. The two core patches and the sidebar patches stay local
until upstream accepts them; they are part of the build, not a post-install
step.
