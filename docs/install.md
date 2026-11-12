# Install

This page takes one Windows machine and one Mac to a working `anix` and `amac`.
Apple silicon and Intel Macs are supported. The installer does the setup. You
answer prompts and approve the few steps that Windows and macOS reserve for a
person.

## Before you start

- Windows 11 with WSL 2.4.4 or later.
- Apple silicon or Intel Mac on macOS 26.2 or later.
- Tailscale signed in on Windows and macOS, with MagicDNS enabled.
- An Apple ID for Xcode 26.6 and iOS builds.

You do not need Nix, Git, or a previous checkout. The installer adds them.
Decide two names now. The anix name is the Linux login. The amac name is the
macOS account short name, which `whoami` prints on the Mac.

The project root defaults to `src` under the anix home. If your projects
already live in `code`, `projects`, or an absolute path, keep them there and
use that parent as `projectsDir`. The directories keep their names; `provision`
copies the ones you select into the NixOS home. An absolute root must already
exist on the NixOS-WSL disk and start with `/home` or `/mnt`; a Windows drive
under `/mnt/c` cannot be exported over NFS, so use a relative root there.

Two limits apply before the first switch. nixpkgs 26.05 is the last release
that builds for `x86_64-darwin`, so an Intel Mac stops receiving Nix security
updates on 2026-12-31. The installer warns when it detects one. FileVault stays
off so the Mac can auto-login and accept SSH after a reboot.

## Fork the repository

Create your fork at https://github.com/win0na/anix/fork. The installer clones
your fork, and the bootstrap writes your keys and usernames there. Commit them
when it finishes. Do not point it at the template unless you plan to re-point
the remote before the first push.

## Path A: Ubuntu WSL

Use this when the WSL distribution you use today has your projects. Run one
command in Ubuntu. It needs no edits; the installer asks for your values.

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/win0na/anix/main/scripts/install)
```

The installer asks for:

1. Your fork URL. Create one at the link above, then paste it here.
2. The Linux username for anix. The default is `$USER`.
3. The macOS short name for amac. Run `whoami` on the Mac if you are unsure.
4. The project root. The default is `src`; type `code` or an absolute path if
   your projects already live there.

Then it installs Nix, clones the fork to `~/src/anix`, creates the personal age
key, the Mac builder key, `.sops.yaml`, and `secrets/secrets.yaml`, and starts
`scripts/provision`.

`provision` exports Ubuntu, installs NixOS-WSL alongside it, transfers the
repository and the projects you select, runs the anix bootstrap, and prepares
the Mac. Ubuntu stays until both hosts pass, and it is removed only after you
type the distribution name.

Approve the Windows UAC prompt when it appears. Enable Remote Login on the Mac
when the Mac phase starts.

## Path B: fresh Windows

Use this when there is no Ubuntu WSL worth keeping. Create your fork, then run
this block in an elevated PowerShell. It needs no edits; the helper asks for
your fork URL, both usernames, and the project root.

```powershell
irm https://raw.githubusercontent.com/win0na/anix/main/scripts/bootstrap-windows.ps1 -OutFile "$env:TEMP\anix-bootstrap.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\anix-bootstrap.ps1"
```

The helper:

1. Installs WSL if it is missing. Reboot and run the block again if it
   installs WSL.
2. Updates WSL, writes `.wslconfig`, and opens TCP 2049 for the NixOS VM.
3. Downloads and verifies the pinned NixOS-WSL 2605.7.2 image.
4. Installs the distribution, writes both names and the project root to
   `users.nix`, runs the first switch, and clones your fork to `~/src/anix`.
5. Registers the `anix-wsl` logon task and runs `scripts/bootstrap --host
   anix` inside the new distribution.
6. Runs `scripts/bootstrap-mac-remote` to prepare the Mac.

The bootstrap creates the keys and secrets, adds the anix host key as a sops
recipient, switches, and prompts for the GitHub device login used by the VS
Code tunnel. The Mac phase asks for **Remote Login** to be enabled.

If you changed the WSL memory, CPU, or networking settings in `.wslconfig`, run
`wsl --shutdown` in PowerShell and start the distribution again.

## The Mac

Path B runs this phase at the end. For Path A, or to retry, do this from anix
after the anix bootstrap succeeds.

1. On the Mac, open **System Settings > General > Sharing** and enable
   **Remote Login**.
2. Confirm Tailscale is signed in and `amac` resolves.
3. From anix:

   ```sh
   ~/src/anix/scripts/bootstrap-mac-remote
   ```

   The script waits for SSH, installs Nix if it is missing, copies the checkout
   to `~/.config/anix`, generates the Mac host key, adds it as the amac sops
   recipient, and writes `~/anix-first-switch/first-switch.command`.

4. Approve the Terminal and App Management prompts on the Mac. The first
   `darwin-rebuild` runs inside Terminal, not over SSH.

If Terminal does not open, the script prints the command to run on the Mac. The
first switch moves the Nix installer's `/etc/nix/nix.conf`, `/etc/bashrc`, and
`/etc/zshrc` aside, then runs `darwin-rebuild switch`.

Xcode 26.6 is a manual install with an Apple ID and 2FA. After it finishes:

```sh
sudo xcode-select -s /Applications/Xcode-26.6.app
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## Manual steps

These are the steps no script can finish for you. Everything else runs from
the commands above.

| Step | Where | Why |
| --- | --- | --- |
| Fork the repository | GitHub | Your keys, usernames, and secrets live in your copy. |
| Approve UAC | Windows | Installing WSL and the NixOS image needs elevation. |
| Reboot Windows | Windows | The WSL optional component needs it after a fresh install. |
| Approve the Command Line Tools installer | macOS | Nix needs the compiler tools. |
| Sign in to Tailscale | Windows and macOS | MagicDNS and the NFS route depend on it. |
| Enable Remote Login | macOS | `bootstrap-mac-remote` reaches the Mac over SSH. |
| Approve Terminal and App Management | macOS | The first `darwin-rebuild` touches protected paths. |
| Install Xcode | macOS | Xcode needs an Apple ID and 2FA. |

## Flags

`scripts/install` accepts:

| Flag | Effect |
| --- | --- |
| `REPO_URL` | Fork URL as the first positional argument. |
| `--anix-user NAME` | Linux login. Default `$USER`. |
| `--mac-user NAME` | macOS short name. Default `amac`. |
| `--yes` | Accept defaults. It still never unregisters Ubuntu. |
| `--dry-run` | Print the plan and change nothing. |
| `--no-pull` | Do not pull an existing checkout. |
| `--ensure-nix` | Install Nix if missing, then exit. Used by the other scripts. |

`scripts/provision` accepts the flags in
[Reference](reference.md#commands), including `--distro`, `--backup`,
`--no-transfer`, `--no-mac`, and `--no-finalize`.

## After both hosts pass

```sh
scripts/check.sh
ssh amac uname -m
```

`check.sh` evaluates both host configurations and runs `bash -n`, shellcheck,
and typos. The SSH command prints `arm64` on Apple silicon or `x86_64` on
Intel.

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
