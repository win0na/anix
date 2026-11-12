# anix

anix is one Nix flake for a NixOS-WSL development host and an Intel Mac build
machine.

`anix` is the WSL host where you edit and run agents. `amac` builds Darwin and
iOS outputs and stays awake with the lid closed. Both share one Home Manager
configuration, one project tree over NFS, and one encrypted secrets file.

## Hosts

| Host | Platform | Role | Channel | Rebuild |
| --- | --- | --- | --- | --- |
| `anix` | NixOS-WSL, x86_64-linux | Editor, agents, NFS server | `nixos-unstable` | `scripts/rebuild` |
| `amac` | macOS 26, Intel, x86_64-darwin | Darwin and iOS builds | `nixpkgs` 26.05 | `scripts/rebuild amac` |

## Requirements

- Windows 11 with WSL 2.4.4 or later.
- Intel MacBookPro16,1 on macOS 26.2 or later. Apple silicon is not supported.
- Tailscale signed in on Windows and macOS, with MagicDNS enabled.
- An Apple ID for Xcode 26.6 and iOS builds.

The installer adds Nix and the other tools. Two limits matter before you start.
nixpkgs 26.05 is the last release that builds `x86_64-darwin`, so the Mac stops
receiving Nix security updates on 2026-12-31. FileVault stays off so the Mac can
auto-login and accept SSH after a reboot.

## How it works

`flake.nix` defines both hosts and shares the Home Manager modules that have
options on both platforms. The WSL host exports `~/src` over NFSv4.1, and the
Mac mounts it at `$ANIX_MAC_HOME/src`, so projects have one copy. Secrets are
encrypted with sops and age; each host decrypts at activation with its SSH host
key. `scripts/rebuild` picks the host OS, or takes `anix` or `amac`.

## Install

Fork this repository first. The installer clones your fork, creates your keys,
and runs the host install. Replace `<you>` with your GitHub account,
`<anix-user>` with the Linux login, and `<mac-user>` with the macOS short name
that `whoami` prints on the Mac.

### Ubuntu WSL

Run this in your existing Ubuntu distribution:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/<you>/anix/main/scripts/install)
```

The installer asks for your fork URL, the Linux username, and the macOS short
name. It installs Nix, clones the fork to `~/src/anix`, creates the age and
builder keys, and starts `scripts/provision`. Approve the Windows UAC prompt,
and enable Remote Login on the Mac when the script asks.

### Fresh Windows

Run this in an elevated PowerShell:

```powershell
$repo = "https://github.com/<you>/anix.git"
$script = "$env:TEMP\anix-bootstrap.ps1"
irm https://raw.githubusercontent.com/<you>/anix/main/scripts/bootstrap-windows.ps1 -OutFile $script
powershell -ExecutionPolicy Bypass -File $script -RepoUrl $repo -AnixUser <anix-user> -MacUser <mac-user>
```

The helper installs WSL if it is missing, opens TCP 2049, installs the pinned
NixOS-WSL image, runs the first switch, clones your fork, runs the anix
bootstrap, and prepares the Mac. Reboot first if it installs WSL.

### Mac

Path B runs this phase for you. Otherwise, enable Remote Login on the Mac and
run this from anix:

```sh
~/src/anix/scripts/bootstrap-mac-remote
```

Approve the Terminal and App Management prompts when they appear on the Mac.

## Keys and secrets

The first run creates the personal age key at `~/.config/sops/age/keys.txt`,
the builder key at `~/.ssh/mac-builder`, and the encrypted
`secrets/secrets.yaml`. The personal key is the only file you cannot
regenerate. Copy it to a password manager before the first switch.

`.sops.yaml` stays local and gitignored, so your fork never inherits another
person's recipient. Commit `secrets/secrets.yaml` and the public values the
bootstrap writes to `home/default/amac.nix` and `users.nix`.

[Secrets](docs/secrets.md) covers adding, rotating, and recovering keys.

## Rebuild and update

```sh
scripts/rebuild       # current host
scripts/rebuild anix  # NixOS-WSL
scripts/rebuild amac  # local Mac, or over SSH from anix
nix flake update      # move inputs
```

Rebuild both hosts after an input update. `scripts/check.sh` evaluates both
configurations and runs `bash -n`, shellcheck, and typos.

## Docs

- [Install](docs/install.md): the full walkthrough, flags, and manual steps.
- [Secrets](docs/secrets.md): keys, recipients, rotation, recovery.
- [Operate](docs/operate.md): rebuild, update, backups, NFS, and tunnel.
- [Reference](docs/reference.md): hosts, paths, ports, commands, limits.
- [Herdr](docs/herdr.md): the editor stack.
- [Troubleshooting](docs/troubleshooting.md): symptoms and fixes.

## License

MIT
