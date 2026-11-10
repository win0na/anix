# Scripts

The scripts are the user-facing entry points. They live in `scripts/` and run
from any directory. Exit codes are `0` for success, `1` for an environment or
runtime failure, and `2` for a usage error.

| Script | Runs on | Purpose |
| --- | --- | --- |
| `rebuild` | Both | Rebuild and activate one host |
| `bootstrap-wsl.sh` | NixOS-WSL | Clone, check, and switch anix |
| `bootstrap-mac.sh` | macOS | Install Nix, clone, check, and switch amac |
| `migrate-projects.sh` | Linux or WSL | Move projects into `~/src` and leave symlinks |
| `ios` | WSL or macOS | Build an iOS app on the Mac and install it |
| `install-herdr-plugins.sh` | Both | Link the first-party Herdr plugin |
| `check.sh` | Both | Evaluate both hosts and lint the scripts |
| `mount-src` | macOS | Mount the NFS export at `/Users/winona/src` |

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

## scripts/bootstrap-wsl.sh

```text
scripts/bootstrap-wsl.sh [--no-switch] [--repo URL]
```

Checks that the host is NixOS-WSL, clones to `$HOME/src/anix` when absent,
warns when `$HOME/.config/sops/age/keys.txt` is missing, and runs
`sudo nixos-rebuild switch --flake $HOME/src/anix#anix`.

`--no-switch` stops after the checks and the clone. `--repo` overrides
`ANIX_REPO_URL` and the default `https://github.com/win0na/anix.git`. The
script never pulls an existing checkout.

## scripts/bootstrap-mac.sh

```text
scripts/bootstrap-mac.sh [--no-switch] [--install-nix] [--repo URL]
```

Checks Darwin, `x86_64`, macOS 26.x, and the command line tools. With
`--install-nix`, it runs the upstream daemon installer when `nix` is missing.
It clones to `$HOME/.config/anix`, warns when the age key is missing, and runs
`sudo darwin-rebuild switch --flake $HOME/.config/anix#amac`.

The script warns when `SSH_CONNECTION` is set: the first switch should run from
a GUI Terminal because of macOS App Management. On a machine without
`darwin-rebuild`, it moves the installer's `/etc/nix/nix.conf`, `/etc/bashrc`,
and `/etc/zshrc` to `*.before-nix-darwin`, then runs
`nix run github:LnL7/nix-darwin/nix-darwin-26.05#darwin-rebuild`. It never pulls
an existing checkout.

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
command registers the plugin enabled; there is no `--enabled` flag. The script
prints the pinned commits for `herdr-bar`, `herdr-sidebar`, and `ttt.editor`,
which Home Manager installs declaratively, and finishes with
`herdr plugin list`.

## scripts/check.sh

```text
scripts/check.sh
```

Evaluates both system derivations:

```text
.#nixosConfigurations.anix.config.system.build.toplevel.drvPath
.#darwinConfigurations.amac.config.system.build.toplevel.drvPath
```

Then runs `bash -n` on every file in `scripts/`, and `shellcheck` when it is on
`PATH`. It stops on the first failure and prints `check: ok` on success. It
requires `nix`; it does not install anything.

## scripts/mount-src

```text
scripts/mount-src
```

Mounts `ANIX_NFS_HOST:/` at `ANIX_MOUNT_POINT` with
`vers=4.1,resvport,rw,noowners,hard,intr,rsize=131072,wsize=131072,bg`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ANIX_NFS_HOST` | `anix` | NFS server. Set it to the Windows Tailscale node. |
| `ANIX_MOUNT_POINT` | `/Users/winona/src` | Local mount point |

The default host is a placeholder: `anix` is the WSL hostname, not the Windows
Tailscale name. The script warns when `ANIX_NFS_HOST` is unset. It waits up to
60 seconds for Tailscale and TCP 2049, exits `0` when the mount already exists,
and uses `sudo` only when it is not root.
