# Operate

Daily work happens on anix. The Mac is a build target and an NFS client.

## Rebuild

```sh
scripts/rebuild          # current host
scripts/rebuild anix     # NixOS-WSL
scripts/rebuild amac     # local Mac, or over SSH from anix
```

The wrapper picks `anix` on Linux and `amac` on Darwin when you give no target.
It runs `nixos-rebuild switch` or `darwin-rebuild switch` from the checkout.

## Update

```sh
nix flake update
scripts/check.sh
scripts/rebuild
scripts/rebuild amac
```

anix follows `nixos-unstable`; amac follows `nixpkgs` 26.05 through a separate
input. Update both hosts in the same session, then check them.

## Check

```sh
scripts/check.sh
```

It evaluates both host configurations, then runs `bash -n`, shellcheck, and
typos over the repository. Missing tools come from `nix shell nixpkgs#...`, so the
check works before either host is installed.

## Backups

Keep two things outside the repository: the personal age key in a password
manager, and the optional recovery key offline. The encrypted
`secrets/secrets.yaml` is committed to your fork and is the ciphertext backup.

The repository holds the configuration. Projects live in `~/src` on anix. The
Mac holds build outputs only; both can be rebuilt from the fork.

Host SSH keys are not backed up. If one is lost, regenerate it with
`sudo ssh-keygen -A`, add the new recipient, run `sops updatekeys`, and rebuild
that host.

## NFS

anix exports `/home/<anix>/src` to amac over Tailscale. The Mac mounts it at
`$ANIX_MAC_HOME/src`. A launchd daemon named `anix-nfs` runs
`~/.config/anix/scripts/mount-src` at login and retries when the server is not
ready.

```sh
sudo ~/.config/anix/scripts/mount-src
```

`ANIX_NFS_HOST` changes the server name; the default is `anix`, the Windows
Tailscale node name. Set it if your Windows node has a different name.
`ANIX_MOUNT_POINT` changes the mount point. The export squashes all clients to uid 1000 on anix, so file ownership
is the same on both hosts.

File watchers on the Mac do not see remote changes reliably. Keep build
artifacts on local disk, and run editors on anix.

## Remote builds

anix sends Darwin builds to amac over SSH with `ssh-ng`. The builder advertises
both `aarch64-darwin` and `x86_64-darwin`; the Mac serves its own architecture.
The builder key is the `mac-builder-key` secret, installed at
`/etc/nix/mac-builder` on anix. The Mac trusts the amac user through
`nix.settings.trusted-users`.

Root's SSH client on anix needs the Mac host key once:

```sh
sudo ssh -i /etc/nix/mac-builder -o StrictHostKeyChecking=accept-new <mac-user>@amac true
```

That records the key in root's `known_hosts` and confirms the builder key
works.

Test a Darwin build from anix. Use the Mac's architecture:

```sh
# Apple silicon
nix build --no-link .#packages.aarch64-darwin.herdr
# Intel
nix build --no-link .#packages.x86_64-darwin.herdr
```

## VS Code tunnel

anix runs Microsoft's `code tunnel` as a systemd service. It connects outbound
to Microsoft over TCP 443 and does not listen for inbound connections, so no
firewall rule is needed. The token is local OAuth state in
`~/.vscode/cli/token.json`.

VS Code on amac connects to the tunnel and opens `/home/<anix>/src`. The NFS
mount is for Finder and other local tools, not for the editor.

## Power

The Mac runs with the lid closed: `pmset` disables sleep and hibernation,
enables wake on network, and restarts after a power failure. FileVault stays
off so auto-login can start it after a reboot.

## Cache

A Cachix token can live in `secrets/secrets.yaml` for a cache named `anix`. No
substituter is configured by the flake, so use the CLI when you need it:

```sh
nix shell nixpkgs#cachix -c cachix push anix
```
