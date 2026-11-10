# herdr-sidebar patches

Two patches against `alexarthurs/herdr-sidebar` commit
`081ed133f3faa377438b51ce435fe8a87c439593` (plugin subdirectory
`plugins/herdr-sidebar`). Both are shipped and applied, in that order, by
`pkgs/herdr-sidebar/default.nix`.

- `herdr-sidebar-ttt.patch`: replaces the per-file editor tabs with one
  existing editor pane. It spawns `ttt <file>` detached, then focuses that pane.
  Clicking a file in the explorer uses this path.
- `herdr-sidebar-handoff.patch`: adds "Open in code-server" and
  "Open in VS Code" to the file context menu. Each spawns
  `ttt-handoff code-server <path>` or `ttt-handoff mac <path>` detached; the
  helper validates the path and target.

Apply order matters: `herdr-sidebar-handoff.patch` builds on the ttt-patched
tree.
