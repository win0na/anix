# anix

One Nix flake for a NixOS-WSL development host and an Intel Mac build machine.

anix keeps the WSL development system and the 2019 16-inch MacBook Pro on one
repository, one home configuration, and one project tree. The WSL host runs the
editors and agents. The Mac runs macOS 26 Tahoe, builds Darwin and iOS outputs,
and stays awake with the lid closed.

## Status

The repository is a skeleton. Host configurations land in the next pass. The
scripts and docs describe the intended system; commands that need a host
configuration fail until it exists.

## Features

- **Two hosts, one flake:** `anix` runs NixOS-WSL on nixos-unstable; `amac`
  runs nix-darwin 26.05 on x86_64-darwin.
- **Shared projects:** NFSv4.1 exports `~/src` from anix to
  `/Users/winona/src` on the Mac.
- **Pinned Herdr:** the rootshell fork, two core patches, four pinned plugins,
  and one ttt pane per workspace.
- **Shared OpenCode:** one config, first-party `opencode-dcp-fix`, no caveman
  or moshi.
- **Secrets:** sops-nix with age, host keys, a personal key, and an offline
  recovery key.
- **Simple rebuild:** `scripts/rebuild` detects the host; `scripts/rebuild
  amac` works from WSL.

## Requirements

- Windows 11 with WSL 2.4.4 or later, and NixOS-WSL 26.05.
- Intel MacBookPro16,1 with macOS 26.2 or later. Xcode 26.6 requires 26.2.
- Tailscale on Windows and macOS. WSL uses mirrored networking.
- A Cachix cache named `anix`.

## Bootstrap

Run the scripts on each host after the first NixOS install:

```sh
# On the NixOS-WSL host, as winona
~/src/anix/scripts/bootstrap-wsl.sh

# On the Mac, as winona
~/.config/anix/scripts/bootstrap-mac.sh
```

The first NixOS-WSL switch runs as the image's `nixos` user. See
[docs/bootstrap.md](docs/bootstrap.md) for the full order.

## Rebuild

```sh
scripts/rebuild          # current host
scripts/rebuild anix     # NixOS-WSL
scripts/rebuild amac     # local Mac, or over SSH from WSL
```

## Layout

```
flake.nix
hosts/{anix,amac}
modules/{common,nixos,darwin,home}
home/winona
pkgs/{herdr,nuvio,opencode-dcp-fix,herdr-plugins,herdr-sidebar-patch}
secrets
scripts
docs
```

## Limitations

- nixpkgs 26.05 is the last release that builds x86_64-darwin. The Mac stops
  receiving Nix security updates after 2026-12-31.
- FileVault stays off so the Mac can auto-login and accept SSH after a reboot.
- The Mac sees NFS changes from anix, but file watchers on the Mac do not see
  remote changes reliably. Build artifacts stay on local disk.

## Docs

Start with [docs/index.md](docs/index.md). The most useful pages are
[docs/bootstrap.md](docs/bootstrap.md), [docs/networking.md](docs/networking.md),
[docs/herdr.md](docs/herdr.md), and [docs/troubleshooting.md](docs/troubleshooting.md).

## License

MIT
