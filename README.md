# anix

anix is one Nix flake for a NixOS-WSL development host and a Mac build
machine.

`anix` is the WSL host where you edit and run agents. `amac` builds Darwin and
iOS outputs and stays awake with the lid closed. Both share one Home Manager
configuration, one project tree over NFS, and one encrypted secrets file.

## Hosts

| Host | Platform | Role | Channel | Rebuild |
| --- | --- | --- | --- | --- |
| `anix` | NixOS-WSL, x86_64-linux | Editor, agents, NFS server | `nixos-unstable` | `scripts/rebuild` |
| `amac` | macOS 26, Apple silicon or Intel | Darwin and iOS builds | `nixpkgs` 26.05 | `scripts/rebuild amac` |

## Requirements

- Windows 11 with WSL 2.4.4 or later.
- Apple silicon or Intel Mac on macOS 26.2 or later. The installer detects the
  architecture.
- Tailscale signed in on Windows and macOS, with MagicDNS enabled.
- An Apple ID for Xcode 26.6 and iOS builds.

The installer adds Nix and the other tools. Two limits matter before you start.
nixpkgs 26.05 is the last release that builds `x86_64-darwin`, so an Intel Mac
stops receiving Nix security updates on 2026-12-31. The installer prints a
warning when it detects one. FileVault stays off so the Mac can auto-login and
accept SSH after a reboot.

On packages, the two Macs differ: Apple silicon uses Homebrew, and Intel uses
MacPorts with a `brew` shim, so scripts that call `brew` keep working. Casks
still go to Homebrew on both.

## How it works

`flake.nix` defines both hosts and shares the Home Manager modules that have
options on both platforms. The WSL host exports the configured project root
over NFSv4.1, and the Mac mounts it at `$ANIX_MAC_HOME/<name>`, so projects
have one copy. Secrets are encrypted with sops and age; each host decrypts at
activation with its SSH host key. `scripts/rebuild` picks the host OS, or takes
`anix` or `amac`.

## Install

Create your fork at https://github.com/win0na/anix/fork. The installer asks for
the fork URL and both usernames, so the commands below need no edits. It
installs Nix, clones the fork, creates your keys, and runs the host install.

### Ubuntu WSL

Run this in your existing Ubuntu distribution:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/win0na/anix/main/scripts/install)
```

The installer asks for your fork URL, the Linux username, and the macOS short
name. It installs Nix, clones the fork to `~/.config/anix`, creates the age and
builder keys, and starts `scripts/provision`. Approve the Windows UAC prompt,
and enable Remote Login on the Mac when the script asks.

The project root defaults to `~/src`. To keep projects in `~/code` or an
absolute path under the anix home or `/mnt`, set `projectsDir` in `users.nix`;
`scripts/provision` asks for it and writes the value.

### Fresh Windows

Run this in an elevated PowerShell:

```powershell
irm https://raw.githubusercontent.com/win0na/anix/main/scripts/bootstrap-windows.ps1 -OutFile "$env:TEMP\anix-bootstrap.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\anix-bootstrap.ps1"
```

The helper asks for the fork URL, the Linux username, the macOS short name, and
the project root. It installs WSL if it is missing, opens TCP 2049, installs the
pinned NixOS-WSL image, runs the first switch, clones your fork, runs the anix
bootstrap, and prepares the Mac. Reboot first if it installs WSL.

### Mac

Path B runs this phase for you. Otherwise, enable Remote Login on the Mac and
run this from anix:

```sh
~/.config/anix/scripts/bootstrap-mac-remote
```

Approve the Terminal and App Management prompts when they appear on the Mac.

## Keys and secrets

The first run creates the personal age key at `~/.config/sops/age/keys.txt`,
the builder key at `~/.ssh/mac-builder`, and the encrypted
`secrets/secrets.yaml`. The personal key is the only file you cannot
regenerate. `scripts/bootstrap --prepare` prints its path and offers to create
an offline recovery key; copy the personal key to a password manager before the
first switch.

The bootstrap commits `.sops.yaml` (public recipients only), `secrets/secrets.yaml`,
and the values it writes to `home/default/amac.nix` and `users.nix`. You push
them from the checkout. Tracking `.sops.yaml` keeps the anix, Mac, and recovery
recipients on a fresh clone; if it is missing, `sops updatekeys` rebuilds the
list from the personal key alone and drops the others.

[Secrets](docs/secrets.md) covers adding, rotating, and recovering keys.

## Rebuild and update

```sh
scripts/rebuild       # current host
scripts/rebuild anix  # NixOS-WSL
scripts/rebuild amac  # local Mac, or over SSH from anix
nix flake update      # move inputs
```

Rebuild both hosts after an input update. `scripts/check.sh` evaluates both
configurations, parses the Windows helper with pwsh, and runs `bash -n`,
shellcheck, and typos.

## Docs

- [Install](docs/install.md): the full walkthrough, flags, and manual steps.
- [Secrets](docs/secrets.md): keys, recipients, rotation, recovery.
- [Operate](docs/operate.md): rebuild, update, backups, NFS, and tunnel.
- [Reference](docs/reference.md): hosts, paths, ports, commands, limits.
- [Herdr](docs/herdr.md): the editor stack.
- [Troubleshooting](docs/troubleshooting.md): symptoms and fixes.

## License

MIT
