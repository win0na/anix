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
The Herdr tab bar is hidden. The `herdr-ide` layout action is idempotent: it
finds or creates each pane, resizes the split, and focuses the center pane.

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

1. Resolves the workspace's ttt socket directory.
2. Spawns `ttt <file>` with that `TMPDIR`, detached.
3. Focuses the existing ttt pane.

ttt uses `reuseWindow = true`, so the new process forwards the open request to
the newest socket in `$TMPDIR/ttt-uid/` and exits. The patch does not type into
the ttt pane. `pane.send_input` writes to the foreground TUI, which would send
the path as editor keystrokes.

The per-workspace `TMPDIR` is what keeps one ttt instance per workspace. Without
it, `reuseWindow` can forward to the newest socket from another workspace.

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
a tab, and on a hit it focuses the tab. The patch replaces that behavior with a
single editor pane:

- Find the workspace editor pane.
- If it exists, spawn ttt with the file and focus the pane.
- If it does not, create the pane, then spawn ttt and focus it.

The patch targets commit `081ed133f3faa377438b51ce435fe8a87c439593` and will be
applied as a Nix overlay. It is small enough to upstream. The upstream pull
request is part of the work, not a later cleanup.

## ttt

ttt is a Go TUI editor with built-in LSP, ripgrep search, a multi-root tree,
tabs, git staging, and an integrated terminal. It has no debug adapter, no VSIX
extensions, and no per-root LSP instances. The config sets Catppuccin mocha,
`reuseWindow`, `focusOnOpen`, `formatOnSave`, and LSP servers for Rust,
TypeScript and JavaScript, Go, Swift, Nix, Python, and Markdown.

The exact settings and LSP commands are in
[Herdr reference](herdr-reference.md).

## What stays manual

- The `herdr-ide` layout action and the sidebar patch are not in this skeleton.
  They land in the configuration pass.
- Until the sidebar patch lands, the pinned plugin creates a tab per unseen
  file.
- The Herdr Darwin build is not exercised in upstream CI. The first Mac build
  proves the Zig and Rust toolchain.
- ttt cannot attach a debugger or load VSIX extensions. Use Xcode or a terminal
  debugger for those cases.
- The layout script arranges panes; it does not restore editor state.
