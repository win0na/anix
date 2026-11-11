# Herdr

Herdr is the workspace manager. ttt is the editor. The agent or terminal sits in
the center, the file sidebar sits on the left, and one ttt pane sits at the
bottom of each workspace. The goal is a VSCode-shaped layout without forking the
Herdr core for every feature.

## The layout

```text
+----------------------+----------------------------------+
| Explorer             | Agent or terminal                |
| Source Control       |                                  |
|                      |                                  |
+----------------------+----------------------------------+
| ttt, one instance per workspace                         |
+---------------------------------------------------------+
```

The left pane switches between Explorer and Source Control in place. The center
pane runs the agent or a shell. The bottom pane runs ttt at 35 percent height.
The Herdr tab bar is hidden. The `herdr-ide` script runs on `prefix+i`: it
splits the focused pane, starts ttt with a workspace `TMPDIR`, sets the
`hs-ttt-workspace` marker, opens the sidebar, and focuses the agent again.

## The pieces

| Piece | Role |
| --- | --- |
| Herdr core | Pane, tab, and workspace manager. Pinned to the rootshell fork. |
| `responsive-sidebar` | Docks the sidebar on wide tabs and opens it as an overlay on narrow tabs. |
| `herdr-bar` | Status bar. |
| `herdr-sidebar` | Explorer and Source Control. Patched to open files in one ttt pane. |
| `ttt.editor` | Herdr plugin that opens ttt. |
| ttt | The editor process. One per workspace. |

The core carries two patches: a terminal palette setting and a hidden tab bar.
Both are core features that a plugin cannot provide. Everything else is a
plugin.

## Opening a file

The sidebar owns the click. On a file click, the patched sidebar:

1. Finds the pane whose `hs-ttt-workspace` token equals the current workspace.
2. Reads the `hs-ttt-tmpdir` token from that pane.
3. Spawns `ttt <file>` with that `TMPDIR`, detached.
4. Focuses the existing ttt pane.

ttt uses `reuseWindow = true`, so the new process forwards the open request to
the newest socket in `$TMPDIR/ttt-uid/` and exits. The patch does not type into
the ttt pane. `pane.send_input` writes to the foreground TUI, which would send
the path as editor keystrokes.

The per-workspace `TMPDIR` is what keeps one ttt instance per workspace. Without
it, `reuseWindow` can forward to the newest socket from another workspace. The
tokens are ephemeral: a Herdr restart clears pane metadata, so run `herdr-ide`
again after a restart.

## Plugin boundary

Herdr plugins can open, focus, and close panes, send input, read pane output,
and subscribe to workspace, tab, and pane events. They cannot register
keybindings, hide the tab bar, or set the terminal palette. Keybindings live in
`config.toml` and point at plugin actions. The two core patches cover the
features that have no plugin API.

There is no file-open event. The sidebar patch is the integration point, not an
event subscriber.

## The sidebar patch

`herdr-sidebar` already deduplicates per-file editor tabs. On a miss it creates
a tab, and on a hit it focuses the tab. The patch adds a marker lookup before
that path:

- Find the pane with the workspace's `hs-ttt-workspace` token.
- If it exists, spawn ttt with the file and the recorded `TMPDIR`, then focus
  the pane.
- If it does not, keep the stock per-file tab path.

The patch targets commit `081ed133f3faa377438b51ce435fe8a87c439593`. The package
at `pkgs/herdr-sidebar` builds it and the Home Manager activation links the
result over the GitHub install. The patch is small enough to upstream; the pull
request is part of the work, not a later cleanup.

## ttt

ttt is a Go TUI editor with built-in LSP, ripgrep search, a multi-root tree,
tabs, git staging, and an integrated terminal. It has no debug adapter, no VSIX
extensions, and no per-root LSP instances. The config copies the current user
settings: Catppuccin mocha, `reuseWindow`, a collapsed sidebar, and LSP servers
for Rust, TypeScript and JavaScript, Go, Swift, Nix, Python, and Markdown.
`focusOnOpen` and `formatOnSave` are off in that file.

The exact settings and LSP commands are in
[Herdr reference](herdr-reference.md).

## VS Code and code tunnel

VS Code desktop runs on amac and connects to the anix `code tunnel`. The remote
workspace is `/home/default/src`; the NFS mount at `/Users/winona/src` remains
for Finder and other Mac tools, not for VS Code. The tunnel gives VS Code
remote file watching, LSP, terminal, and search on anix.

The handoff is one-way, from ttt or the Herdr sidebar to VS Code. The ttt plugin
reads the current file and cursor and calls `scripts/ttt-handoff`. The patched
sidebar has one "Open in VS Code" menu entry for the selected file. VS Code
opens through SSH with `--reuse-window --remote tunnel+anix --folder-uri
vscode-remote://tunnel+anix/home/default/src --goto`. Browser access is
`https://vscode.dev/tunnel/anix/home/default/src`. There is no live tab or cursor
sync.

The Catppuccin theme under `home/default/ttt/plugins/theme-catppuccin-mocha` is a
port of the official VS Code theme. The VS Code side uses the Catppuccin
extension.

## What stays manual

- The sidebar's `custom_editor_on_click` state and `editor-command.txt` must
  select the custom editor. The state lives under
  `~/.local/state/herdr/plugins/herdr-sidebar`; the plugin settings UI writes
  it. The patch does not override that user choice.
- The Herdr Darwin build is not exercised in upstream CI. The first Mac build
  proves the Zig and Rust toolchain.
- ttt cannot attach a debugger or load VSIX extensions. Use Xcode or a terminal
  debugger for those cases.
- The layout script arranges panes; it does not restore editor state.
- The `herdr-sidebar` build is pinned to commit `081ed13`. A new plugin release
  needs the patch rebased.
