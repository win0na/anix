# anix docs

The docs follow Diataxis. Each page has one type, so you know whether to read
it for a lesson, a task, a fact, or an explanation.

## Tutorials

- [Bootstrap](bootstrap.md): install NixOS-WSL, bring up the Mac, and reach a
  working pair of hosts with the interactive scripts.

## How-to guides

- [Secrets](secrets.md): create age keys, encrypt a secret, add a recipient,
  and recover from a lost key.
- [Troubleshooting](troubleshooting.md): fix NFS, Tailscale, remote builds,
  auto-login, Herdr, and sops failures.

## Reference

- [Scripts](scripts.md): every user-facing script, its usage, and its exit
  codes.
- [Herdr reference](herdr-reference.md): plugin pins, ttt settings, LSP
  servers, and keybindings.
- [macOS](macos.md): power settings, casks, defaults, Xcode, and media apps.

## Explanation

- [Architecture](architecture.md): the two hosts, the flake graph, the NFS
  boundary, and the build flow.
- [Networking](networking.md): Tailscale, WSL mirrored mode, NFSv4.1, and the
  remote builder.
- [Herdr](herdr.md): the IDE layout, the plugin boundary, and the single ttt
  pane.
- [OpenCode](opencode.md): the shared config, MCP servers, plugins, and
  secrets.
- [Decisions](decisions.md): the choices behind the layout, with their
  consequences.
