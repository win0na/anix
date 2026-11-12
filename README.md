# anix

One Nix flake for a NixOS-WSL development host and an Intel Mac build machine.

`anix` is the WSL host where you edit and run agents. `amac` is the Mac that
builds Darwin and iOS outputs and stays awake with the lid closed. Both share
one Home Manager configuration, one project tree over NFS, and one encrypted
secrets file.

## Hosts

| Host | Platform | Role | Channel | Rebuild |
| --- | --- | --- | --- | --- |
| `anix` | NixOS-WSL, x86_64-linux | Editor, agents, NFS server | `nixos-unstable` | `scripts/rebuild` |
| `amac` | macOS 26, Intel, x86_64-darwin | Darwin and iOS builds | `nixpkgs` 26.05 | `scripts/rebuild amac` |

## Requirements

- Windows 11 with WSL 2.4.4 or later.
- Intel MacBookPro16,1 on macOS 26.2 or later. Apple silicon is not supported.
- Tailscale signed in on Windows and macOS.
- Nix on the host that runs the install.
- An Apple ID for Xcode 26.6 and iOS builds.

Two limits matter before you start. nixpkgs 26.05 is the last release that
builds for `x86_64-darwin`, so the Mac stops receiving Nix security updates on
2026-12-31. FileVault stays off so the Mac can auto-login and accept SSH after
a reboot, which means anyone with physical access can read its keys.

## How it works

`flake.nix` defines both hosts and shares Home Manager modules where both
platforms have the option. The WSL host exports `~/src` over NFSv4.1 and the
Mac mounts it at `$ANIX_MAC_HOME/src`, so projects have one copy. Secrets are
encrypted with sops and age; each host decrypts at activation with its SSH host
key. `scripts/rebuild` picks the host from the OS, or takes `anix` or `amac`.

## Install

Both paths end with the same two hosts. Pick the one that matches the machine
in front of you.

### From an existing Ubuntu WSL

1. Fork this repository and clone your fork inside Ubuntu.

   ```sh
   git clone https://github.com/<you>/anix.git ~/src/anix
   ```

2. Install Nix if it is missing, then create the key material.

   ```sh
   ~/src/anix/scripts/bootstrap --prepare
   ```

   This writes your personal age key, the Mac builder key, `.sops.yaml`, and
   `secrets/secrets.yaml`. Keep the age key; it is the only file you cannot
   regenerate.

3. Enable Remote Login on the Mac, then run the installer from the same
   checkout.

   ```sh
   ~/src/anix/scripts/provision
   ```

   It exports Ubuntu, installs NixOS-WSL alongside it, transfers the repository
   and the projects you select, runs the anix bootstrap, and prepares the Mac.
   Ubuntu stays until both hosts pass and you type its distribution name.

4. Approve the Terminal and App Management prompts on the Mac when the first
   switch asks.

5. Check the result.

   ```sh
   ~/src/anix/scripts/check.sh
   ssh amac uname -m
   ```

   The second command prints `x86_64`.

### From a fresh Windows machine

1. Fork this repository and set both names in `users.nix`. `amac` must be the
   macOS short name, which `whoami` prints on the Mac.
2. Download `scripts/bootstrap-windows.ps1` from your fork and run it in an
   elevated PowerShell.

   ```powershell
   .\bootstrap-windows.ps1 -RepoUrl https://github.com/<you>/anix.git -AnixUser <name>
   ```

   It updates WSL, opens TCP 2049, installs the pinned NixOS-WSL image, runs the
   first switch, clones your fork to `~/src/anix`, and registers the logon task.

3. Start the distribution and finish the anix side.

   ```sh
   ~/src/anix/scripts/bootstrap --host anix
   ```

4. Enable Remote Login on the Mac, then run the Mac phase from anix.

   ```sh
   ~/src/anix/scripts/bootstrap-mac-remote
   ```

5. Run `scripts/check.sh` and `ssh amac uname -m` as above.

## Keys and secrets

`--prepare` creates the personal age key at `~/.config/sops/age/keys.txt`, the
builder key at `~/.ssh/mac-builder`, and an encrypted `secrets/secrets.yaml`
holding the builder key plus an optional Cachix token and Mac login password.
It stages the encrypted file so Nix can see it; commit it to your fork as the
ciphertext backup. `.sops.yaml` stays local and gitignored, so a fork never
inherits another person's recipient.

Host keys are added as recipients by the bootstrap scripts. The offline
recovery key is optional and is generated on request.

[Secrets](docs/secrets.md) covers adding, rotating, and recovering keys.

## Rebuild and update

```sh
scripts/rebuild          # current host
scripts/rebuild anix     # NixOS-WSL
scripts/rebuild amac     # local Mac, or over SSH from anix
nix flake update         # move the inputs
```

Rebuild both hosts after an input update. `scripts/check.sh` evaluates both
configurations, runs `bash -n`, shellcheck, and typos.

## Layout

```text
flake.nix          inputs, both host outputs, packages
users.nix          the anix and amac usernames
hosts/anix         WSL host: user, NFS export, builder client, sops
hosts/amac         Mac host: user, Homebrew, power, NFS mount, sops
modules/common     options that exist on both platforms
modules/nixos      NixOS-only options
modules/darwin     nix-darwin-only options
modules/home       Home Manager modules shared by both hosts
home/default       the shared home configuration
pkgs/              Herdr, ttt, fff, the sidebar, Nuvio, and OpenCode packages
scripts/           install, rebuild, mount, and check entry points
secrets/           the encrypted file and its schema
```

## What next

- Add a package to `home/default/default.nix`, then run `scripts/rebuild`.
- Change a host setting in `hosts/anix` or `hosts/amac`.
- Rotate the personal key in [Secrets](docs/secrets.md).
- Read [Operate](docs/operate.md) before changing NFS, the tunnel, or backups.

## Docs

- [Install](docs/install.md): the full walkthrough, including the key setup.
- [Secrets](docs/secrets.md): keys, recipients, rotation, recovery.
- [Operate](docs/operate.md): rebuild, update, backups, NFS, and the tunnel.
- [Reference](docs/reference.md): hosts, paths, ports, commands, limits.
- [Herdr](docs/herdr.md): the editor stack.
- [Troubleshooting](docs/troubleshooting.md): symptoms and fixes.

## License

MIT
