# Scripts

The scripts are the user-facing entry points. They live in `scripts/` and run
from any directory. Exit codes are `0` for success, `1` for an environment or
runtime failure, and `2` for a usage error.

| Script | Runs on | Purpose |
| --- | --- | --- |
| `rebuild` | Both | Rebuild and activate one host |
| `provision` | Ubuntu WSL | Orchestrate the NixOS-WSL replacement, transfer, anix bootstrap, and Mac phase |
| `bootstrap` | Both | Interactive first run for one host: keys, secrets, recipients, and switch |
| `bootstrap-mac-remote` | anix | Prepare a fresh Mac over SSH and start its first switch |
| `bootstrap-windows.ps1` | Windows | Prepare WSL, the firewall, the NixOS image, and the logon task |
| `bootstrap-wsl.sh` | NixOS-WSL | Alias for `bootstrap --host anix` |
| `bootstrap-mac.sh` | macOS | Alias for `bootstrap --host amac` |
| `apw` | Both | Stub for the Passwords.app adapter; storage commands exit 5 |
| `migrate-projects.sh` | Linux or WSL | Move projects into `~/src` and leave symlinks |
| `ios` | WSL or macOS | Build an iOS app on the Mac and install it |
| `install-herdr-plugins.sh` | Both | Link the first-party Herdr plugin |
| `herdr-ide` | Both | Build the sidebar, agent, and ttt layout |
| `check.sh` | Both | Evaluate both hosts, lint the scripts, and run typos |
| `mount-src` | macOS | Mount the NFS export at `$ANIX_MAC_HOME/src` |

## scripts/provision

```text
scripts/provision [--distro NAME] [--anix-user USER] [--mac-user USER]
                  [--mac-host HOST] [--dir PATH] [--backup PATH]
                  [--image-url URL] [--image-sha SHA]
                  [--no-transfer] [--no-mac] [--no-finalize]
                  [--skip-backup] [--dry-run] [--yes]
```

Run in the old Ubuntu WSL distribution. It installs NixOS-WSL alongside
Ubuntu, runs the first boot as `nixos`, transfers the selected trees and keys,
runs `scripts/bootstrap --host anix`, and calls
`scripts/bootstrap-mac-remote`. It backs up Ubuntu first and leaves it in place
unless you confirm removal at the end. `--yes` accepts defaults but never
unregisters Ubuntu. `--no-transfer` skips the project checklist; the keys and
repository still transfer. `--dry-run` prints the phases without changing either
host.

The project checklist scans the top level of `$HOME` and `$HOME/src`. It
excludes hidden directories, `src/anix`, `target`, `node_modules`,
`DerivedData`, and other build outputs.

## scripts/bootstrap-mac-remote

```text
scripts/bootstrap-mac-remote [--mac-host HOST] [--mac-user USER]
                             [--anix-user USER] [--yes] [--dry-run]
                             [--no-first-switch]
```

Run on anix after the anix bootstrap. It waits for SSH to the Mac, checks the
Intel architecture, installs Nix if needed, copies the repository to
`~/.config/anix`, generates the Mac host key, adds the amac recipient with
`sops updatekeys`, writes `~/anix-first-switch/first-switch.command`, opens it
in the logged-in Terminal, and polls for `post.ok`. The macOS App Management,
Homebrew, and sudo prompts happen in that Terminal. `--no-first-switch` stops
after the recipient is added.

## scripts/apw

```text
scripts/apw secret exists|get|set|delete|verify NAME
scripts/apw backup check [NAME]
scripts/apw version
```

A stub for the future Passwords.app adapter. It never reads or writes a secret
on Linux; storage commands print the manual instruction and exit 5. `APW_MODE`
accepts `auto`, `required`, or `off`.

## scripts/rebuild

```text
scripts/rebuild [anix|amac]
```

With no target, `uname -s` selects `amac` on Darwin and `anix` on Linux.

- `anix` requires Linux and `nixos-rebuild`. It runs
  `sudo nixos-rebuild switch --flake REPO#anix`.
- `amac` on Darwin requires `darwin-rebuild`. It runs
  `sudo darwin-rebuild switch --flake REPO#amac`.
- `amac` on Linux checks `ssh -o BatchMode=yes -o ConnectTimeout=5 amac true`,
  then runs the pull and switch on the Mac over SSH.

Exit `2` for an unknown target or too many arguments. `--help` exits `0`.

## scripts/bootstrap

```text
scripts/bootstrap [--host anix|amac] [--yes] [--dry-run] [--no-switch]
                  [--install-nix] [--no-install] [--force-ssh] [--repo URL]
```

The interactive first run. It detects the host from `uname`, checks the
environment, restores or creates the personal age key and the Mac builder key,
creates or updates `secrets/secrets.yaml`, adds the host recipient to
`.sops.yaml`, runs `sops updatekeys`, and switches the host. It asks before
committing and before pushing.

`--host` selects `anix` or `amac` when detection is wrong. `--yes` accepts the
prompts; it cannot invent a missing secret. `--dry-run` prints the actions
without changing anything. `--no-switch` stops before the switch.
`--install-nix` installs the upstream daemon on macOS without prompting;
`--no-install` refuses to install. `--force-ssh` allows the first Mac switch
over SSH; the default refuses because macOS App Management can block
`/Applications/Nix Apps`. `--yes` never pushes and never installs Xcode; those
prompts default to no. `--repo` changes the clone URL named in the
missing-checkout error.

On anix, after the switch, it offers the GitHub device login for the VS Code
tunnel. The token is user state at `~/.vscode/cli/token.json`, not a sops
secret. `--yes` prints the login command instead of running it.

The script is idempotent. It skips an existing key, an existing secret, and an
existing recipient. It never unregisters a distribution and never force-pushes.

`bootstrap-wsl.sh` and `bootstrap-mac.sh` are thin aliases that pass
`--host anix` or `--host amac`.

## scripts/bootstrap-windows.ps1

```text
scripts/bootstrap-windows.ps1 [-Yes] [-SkipWslUpdate] [-SkipFirewall]
                              [-NoShutdown] [-NoFirstSwitch] [-NoClone] [-NoTask]
                              [-DistroName NAME] [-AnixUser USER]
                              [-ImageUrl URL] [-ImageSha256 HASH]
                              [-ImagePath PATH] [-Location PATH]
```

Run in an elevated PowerShell. It updates WSL, writes
`%UserProfile%\.wslconfig`, opens TCP 2049 for the WSL VM, downloads and
verifies the NixOS-WSL 2605.7.2 image, and installs it under the requested
name. By default it also runs the first switch, clones the repository for the
anix user, and registers the `anix-wsl` logon task. `scripts/provision` calls it
with `-NoShutdown -NoFirstSwitch -NoClone`, so the orchestrator owns those steps.

If the distribution already exists, it offers to skip the install and run the
remaining steps. It never deletes or unregisters a distribution.

## scripts/migrate-projects.sh

```text
scripts/migrate-projects.sh [--dry-run] [name...]
```

Moves `$HOME/<name>` to `$HOME/src/<name>` and leaves a relative symlink at the
old path. It handles the four states: already a symlink, target exists, source
exists, both exist. It refuses `anix`.

With no names, it lists immediate child directories of `$HOME` that contain
`.git` and exits `1`. `--dry-run` prints the `mkdir`, `mv`, and `ln` commands
without changing anything.

## scripts/ios

```text
scripts/ios <project> <scheme> [device-udid] [--build-only] [--configuration NAME]
```

`project` is an absolute path on the Mac or a directory name under `$HOME/src`.
`device-udid` is required unless `--build-only` is set. The default
configuration is `Release`.

On Linux the body runs through `ssh amac bash -s -- ...`; on macOS it runs
locally. It detects `*.xcworkspace` before `*.xcodeproj`, builds into a
`mktemp` directory under `/tmp` with `-allowProvisioningUpdates`, reads
`TARGET_BUILD_DIR` and `FULL_PRODUCT_NAME` from `-showBuildSettings`, and
installs with `xcrun devicectl device install app --device UDID APP`.

## scripts/install-herdr-plugins.sh

```text
scripts/install-herdr-plugins.sh
```

Links `pkgs/herdr-plugins/responsive-sidebar` with `herdr plugin link`. The
command registers the plugin enabled by default; `--disabled` registers it off.
The script prints the pinned commits for `herdr-bar`, `herdr-sidebar`, and
`ttt.editor`, then finishes with `herdr plugin list`. Home Manager links the
patched `herdr-sidebar` build and copies the Herdr config; the other plugins
stay on their pinned GitHub installs.

## scripts/herdr-ide

```text
scripts/herdr-ide
```

Runs on both hosts. Finds the focused pane, splits it down at 35 percent, starts
ttt with a per-workspace `TMPDIR`, stamps the `hs-ttt-workspace` and
`hs-ttt-tmpdir` tokens, opens the sidebar, and focuses the agent. The Herdr
config binds it to `prefix+i`. Home Manager links it to `~/.local/bin/herdr-ide`.

## scripts/ttt-handoff

```text
scripts/ttt-handoff vscode <path> [line] [col]
```

Opens a file from the ttt plugin or the Herdr sidebar. The path must resolve
under `/home/default/src`; `/../` escapes are rejected. `vscode` SSHes to amac
and runs the app-bundle CLI with `--reuse-window --remote tunnel+anix
--folder-uri vscode-remote://tunnel+anix/home/default/src --goto path:line:col`.
The path travels on stdin; there is no NFS path mapping. VS Code must run in
the GUI session.

## typos

Run `typos` from the repository root. It reads `typos.toml`, which excludes
`flake.lock`, `secrets/`, the vendored Herdr patches, the vendored OpenCode fix,
and the ttt plugins, and lists the project words. Check a file or directory with
`typos path/to/file`.

The Nix hosts install `typos`. `hunspell` stays available for an interactive
prose check with `hunspell -l file.md`.

## scripts/check.sh

```text
scripts/check.sh
```

Evaluates both system derivations:

```text
.#nixosConfigurations.anix.config.system.build.toplevel.drvPath
.#darwinConfigurations.amac.config.system.build.toplevel.drvPath
```

Then runs `bash -n` on every shell script in `scripts/`, `shellcheck` when it is
on `PATH`, and `typos` when it is on `PATH`. The PowerShell script is skipped.
It stops on the first failure and prints `check: ok` on success. It requires
`nix`; it does not install anything.

## scripts/mount-src

```text
scripts/mount-src
```

Mounts `ANIX_NFS_HOST:/` at `ANIX_MOUNT_POINT` with
`vers=4.1,resvport,rw,noowners,hard,intr,rsize=131072,wsize=131072,bg`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ANIX_NFS_HOST` | `anix` | Windows Tailscale node that forwards to WSL nfsd |
| `ANIX_MOUNT_POINT` | `$ANIX_MAC_HOME/src` | Local mount point |

The default `anix` is the Windows Tailscale node, which forwards TCP 2049 to the
WSL NFS server. Set `ANIX_NFS_HOST` only when the tailnet name differs. The
script waits up to 60 seconds for Tailscale and TCP 2049, exits `0` when the
mount already exists, and uses `sudo` only when it is not root.
