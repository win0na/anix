# Install

This page takes one Windows machine and one Intel Mac to a working `anix` and
`amac`. Pick the path that matches the machine you have. Both paths create the
same key material and end with the same two hosts.

## Before you start

- Windows 11 with WSL 2.4.4 or later.
- Intel MacBookPro16,1 on macOS 26.2 or later, signed in to Tailscale.
- Tailscale on Windows, with MagicDNS enabled.
- Nix on the machine that runs `scripts/bootstrap --prepare`. The fresh-Windows
  path installs it inside NixOS-WSL for you.
- An Apple ID for Xcode 26.6 and iOS builds.

Decide two names now. The anix name is the Linux login. The amac name must be
the macOS account short name, which `whoami` prints on the Mac. Both live in
`users.nix`, and the scripts write that file for you on the Ubuntu path.

Fork the repository. The install clones your fork, so the remote URL must point
at your copy, not at the upstream template.

Two limits apply before the first switch. nixpkgs 26.05 is the last release
that builds for `x86_64-darwin`, so the Mac stops receiving Nix security
updates on 2026-12-31. FileVault stays off so the Mac can auto-login and accept
SSH after a reboot.

## Keys and secrets

Every path needs four things:

| Item | Path | Created by |
| --- | --- | --- |
| Personal age key | `~/.config/sops/age/keys.txt` | `scripts/bootstrap` |
| Mac builder key | `~/.ssh/mac-builder` | `scripts/bootstrap` |
| sops config | `.sops.yaml` | `scripts/bootstrap` |
| Encrypted secrets | `secrets/secrets.yaml` | `scripts/bootstrap` |

The personal key is the only file you cannot regenerate. Copy it to a password
manager before the first switch.

Prepare also writes the builder public key into `home/default/amac.nix`. That
file is tracked, so commit the change with the others.

`.sops.yaml` is local and gitignored. A fork never inherits another person's
recipient. The encrypted file is staged for git and should be committed to your
fork once it exists; that commit is the ciphertext backup.

Prepare asks four questions:

1. Generate a personal age key, if one is missing.
2. Generate the Mac builder key, if one is missing.
3. Cachix token, blank to skip.
4. Mac login password, blank to skip.

Then it offers to generate an offline recovery key. Accept it if you have a
place to store the private half.

On the Ubuntu path, install Nix if it is missing
(`sh <(curl -L https://nixos.org/nix/install)`, then open a new shell) and run
prepare before the installer:

```sh
cd ~/src/anix
scripts/bootstrap --prepare
```

The last lines name the next step. On the fresh-Windows path, skip this: the
anix bootstrap inside NixOS creates the same files and asks the same four
questions.

## Path A: from Ubuntu WSL

Use this when the WSL distribution you use today already has your projects and
a Nix install. The installer keeps Ubuntu until the new hosts pass.

Enable Remote Login on the Mac before this step: `provision` runs the Mac phase
at the end and waits for SSH.

```sh
git clone https://github.com/<you>/anix.git ~/src/anix
cd ~/src/anix
scripts/bootstrap --prepare
scripts/provision --anix-user <name> --mac-user <mac-name>
```

`provision` reads the two usernames from `users.nix`. Pass `--anix-user` and
`--mac-user` when they differ from the defaults, and `--distro` or `--backup`
to change those. It prompts for the Ubuntu export and the project checklist,
then:

1. Writes `users.nix` when the names differ from the defaults.
2. Exports Ubuntu with `wsl --export`, encrypted to your personal key.
3. Installs the pinned NixOS-WSL image alongside Ubuntu.
4. Stages the repository without secrets, runs the first `nixos-rebuild boot`
   as `nixos`, and starts the new distribution as your anix user.
5. Transfers the age key, the builder key, the encrypted secrets, and the
   project directories you selected.
6. Runs `scripts/bootstrap --host anix` inside NixOS.
7. Runs `scripts/bootstrap-mac-remote` against the Mac.

The project checklist scans your home and `~/src`. It skips `target`,
`node_modules`, and `DerivedData`. On a rerun, the NixOS copy wins for files
that already exist there.

Useful flags:

| Flag | Effect |
| --- | --- |
| `--anix-user NAME` | Linux login. Default from `users.nix`. |
| `--mac-user NAME` | macOS short name. Default from `users.nix`. |
| `--distro NAME` | New WSL distribution name. Default `NixOS`. |
| `--backup PATH` | Windows path for the Ubuntu export. |
| `--dir PATH` | Transfer an extra directory. Repeatable. |
| `--dry-run` | Print the plan; change nothing. |
| `--no-mac` | Stop after the anix bootstrap. |
| `--no-transfer` | Skip the project checklist; keys and the repository still transfer. |
| `--skip-backup` | Do not export Ubuntu first. |
| `--yes` | Accept defaults. It never unregisters Ubuntu and transfers no projects unless you pass `--dir`. |

Ubuntu is removed only at the end, only after both hosts pass, and only after
you type the exact distribution name. `--yes` never removes it.

## Path B: from a fresh Windows machine

Use this when there is no useful Ubuntu WSL to keep.

1. In your fork, set both names in `users.nix`.
2. Download `scripts/bootstrap-windows.ps1` from your fork.
3. In an elevated PowerShell, run:

   ```powershell
   .\bootstrap-windows.ps1 -RepoUrl https://github.com/<you>/anix.git -AnixUser <name>
   ```

   The script updates WSL, writes `.wslconfig`, opens TCP 2049, downloads and
   verifies the NixOS-WSL image, installs it with `wsl --install --from-file`,
   runs the first switch, clones your fork to `~/src/anix`, and registers the
   `anix-wsl` logon task. It never unregisters a distribution.

4. Start the distribution:

   ```powershell
   wsl -d NixOS
   ```

5. Finish the anix side:

   ```sh
   cd ~/src/anix
   scripts/bootstrap --host anix
   ```

   This creates the keys and secrets on NixOS, adds the anix host key as a sops
   recipient, switches, and prompts for the GitHub device login used by the
   VS Code tunnel.

If you changed the WSL memory, CPU, or networking settings in `.wslconfig`, run
`wsl --shutdown` in PowerShell and start the distribution again.

## The Mac

Do this from anix after the anix bootstrap succeeds.

1. On the Mac, enable Remote Login in System Settings > General > Sharing.
2. Confirm Tailscale is signed in and `amac` resolves.
3. From anix:

   ```sh
   ~/src/anix/scripts/bootstrap-mac-remote
   ```

   The script waits for SSH, installs Nix if it is missing, copies the checkout
   to `~/.config/anix`, generates the Mac host key, adds it as the amac sops
   recipient, and writes `~/anix-first-switch/first-switch.command`.

4. Approve the Terminal and App Management prompts on the Mac when they appear.
   The first `darwin-rebuild` runs inside Terminal, not over SSH.

If Terminal does not open, the script prints the command to run on the Mac. The
first switch moves the Nix installer's `/etc/nix/nix.conf`, `/etc/bashrc`, and
`/etc/zshrc` aside, then runs `darwin-rebuild switch`.

Xcode 26.6 is a manual install with an Apple ID and 2FA. After it finishes:

```sh
sudo xcode-select -s /Applications/Xcode-26.6.app
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## After both hosts pass

```sh
scripts/check.sh
ssh amac uname -m
```

`check.sh` evaluates both configurations and runs `bash -n`, shellcheck, and
typos. The SSH command prints `x86_64`.

On the Mac, confirm the NFS mount and the editor stack:

```sh
mount | grep '/Users/.*/src'
herdr plugin list
```

Then commit what the bootstrap changed in your fork: `secrets/secrets.yaml`,
`home/default/amac.nix`, and `users.nix`. `.sops.yaml` stays local; it is
ignored. Only the encrypted file and public values belong in git.

## If a step stops

Every phase prints the command or file that failed. Fix that item and rerun the
same script; completed phases are skipped. Start with `--dry-run` when you want
to see the plan. [Troubleshooting](troubleshooting.md) covers NFS, SSH, sops,
WSL, and first-switch failures.
