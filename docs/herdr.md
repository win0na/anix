# Editor stack

Herdr manages panes and workspaces. ttt is the editor. A patched sidebar
connects them. OpenCode runs the agents in the center pane.

Two front ends drive the same server:

| Front end | Where | Draws |
| --- | --- | --- |
| Rootshel control mode | iPad, iPhone | Tabs, splits, pane chrome, and the workspace dashboard. |
| Herdr TUI | Desktop terminal | Everything, including the tab bar and status row. |

Both see the same panes. The TUI keeps the `prefix` keybindings; a control
client sends raw terminal bytes and never triggers them, so the same actions
have profile shortcuts in Rootshel.

## Layout

```text
+----------------------+----------------------------------+
| Explorer             | Agent or terminal                |
| Source Control       |                                  |
+----------------------+----------------------------------+
| ttt, one pane per workspace                             |
+---------------------------------------------------------+
```

`herdr-action ide` builds it: it splits the focused pane, starts ttt with a
workspace `TMPDIR`, records `hs-ttt-workspace` and `hs-ttt-tmpdir` on the pane,
opens the sidebar, and focuses the agent again. In the TUI, `prefix+i` runs the
same command. The Herdr tab bar is hidden in the TUI; Rootshel has its own.

## Rootshel control mode

Set the profile's launch command to `herdr-action <action>`, one profile per
action:

| Action | Result |
| --- | --- |
| `ide` | Sidebar, agent, and ttt in the focused workspace. |
| `bar` | `herdr-bar` as a full-tab overlay. |
| `sidebar` | Open or focus the explorer sidebar. |
| `ttt` | Open ttt in a new pane. |

The command talks to the server's focused pane, and tapping a pane on the
device moves that focus. It runs in its own SSH tab, which can be closed once
the action returns. Assign a key to opening the profile, not to the action.

`herdr-action` finds Herdr on `PATH`, then at
`~/.local/opt/herdr-rootshell/bin/herdr`; `HERDR_BIN_PATH` overrides both. For
a named session, put `HERDR_SESSION=<name>` in front of the command.

## Transport

Control mode needs an auxiliary SSH channel. Rootshel's `tssh` transport
provides one: a normal SSH login starts `tsshd`, then the session moves to UDP
and survives roaming. Mosh has no auxiliary channel, so the control stream
cannot run over it.

The repo packages rootshell's `tsshd` fork, which reports `ProtoVer` 3. The
Ubuntu PPA build reports protocol 1 and does not support the control channel.

```sh
nix build .#tsshd
sudo install -m755 result/bin/tsshd /usr/local/bin/tsshd
```

`tsshd` must be on the SSH login `PATH` (`/usr/local/bin` on Ubuntu,
`environment.systemPackages` on NixOS). Rootshel runs it per connection on UDP
ports 61000-61999; that range must reach the host. See
[Operate](operate.md#tssh-transport).

## Pieces

| Piece | Role |
| --- | --- |
| `pkgs/herdr` | Herdr 0.9.5 from the rootshell fork, with two patches. |
| `pkgs/herdr-sidebar` | `alexarthurs/herdr-sidebar` at `081ed13`, with two patches. |
| `pkgs/herdr-plugins` | First-party `responsive-sidebar` plugin. |
| `pkgs/tsshd` | Rootshel's tsshd fork. |
| `pkgs/ttt` | ttt 1.11.0 release binary. |
| `pkgs/fff-mcp` | fff MCP server for OpenCode. |

The core patches hide the tab bar on its own and add a palette fallback. The
sidebar patches replace per-file editor tabs with one ttt pane, and add **Open
in VS Code** to the file context menu. The second one calls `ttt-handoff`, which
opens the file on amac through the code tunnel.

Home Manager links the patched sidebar build. Do not install
`alexarthurs/herdr-sidebar` from GitHub on top of it; that replaces the patched
copy with the stock plugin.

## Plugins under control mode

The sidebar stays a pane. `herdr-sidebar` draws inside a real terminal, so
Rootshell renders it like any other pane; nothing about the explorer, the ttt
handoff, or the VS Code entry changes.

`responsive-sidebar` docks the sidebar on wide tabs and opens an overlay on
narrow ones. That is server-side choreography, and it would fight Rootshel's
own layout. The watcher asks `control.list` on every poll and stands down while
any control stream is attached: it closes the overlays it opened and opens
nothing. When the stream goes away, the TUI gets the dock and overlay
behaviour back.

`herdr-bar` ships as a popup. Its entrypoint also accepts an overlay, which is
what `herdr-action bar` opens: the bar fills the tab, closes itself on exit,
and restores the previous zoom and focus. No plugin patch is needed.

The `hide_tab_bar` and palette settings are TUI-only. A control client draws
its own chrome and palette.

## Keys

| Key | Action |
| --- | --- |
| `prefix+i` | IDE layout (TUI). |
| `prefix+k` | Open `herdr-bar` (TUI). |
| `prefix+e` | Open ttt in the focused pane (TUI). |
| `prefix+s` | Toggle the responsive sidebar (TUI). |

On the device, the same actions are profile shortcuts; see
[Rootshell control mode](#rootshell-control-mode).

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

## Opening links

`xdg-open` on anix sends HTTP(S) links to the Rootshel device. Herdr forwards
the clipboard envelope the wrapper writes, so a link opens in the browser on
the connected device instead of on the host.

Enable **Settings > Terminal > Open Links from Programs** in Rootshel. It is off
by default.

`BROWSER` points at the same wrapper, so tools that spawn a browser use it too.
`ROOTSHELL_OPEN_MODE=openurl|clipboard` selects the transport and
`ROOTSHELL_OPEN=0` falls back to the desktop `xdg-open`.

## What stays manual

Plugin pins live in `flake.nix`. Update a pin, rebuild, and run
`herdr plugin list`. The two core patches and the sidebar patches stay local
until upstream accepts them; they are part of the build, not a post-install
step.
