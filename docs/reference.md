# Reference

## Hosts

| Host | System | Channel | Home | Role |
| --- | --- | --- | --- | --- |
| `anix` | `x86_64-linux` | `nixos-unstable` | `/home/<anix>` | Editor, agents, NFS server, builder client |
| `amac` | `aarch64-darwin` or `x86_64-darwin` | `nixpkgs` 26.05 | `/Users/<amac>` | Darwin and iOS builds, NFS client |

`amac` is the Apple silicon output and `amac-intel` is the Intel output. The
scripts select one from `uname -m`, so use `scripts/rebuild amac` on either.

Both usernames live in `users.nix`; commands write them as `<anix-user>` and
`<mac-user>`. `projectsDir` in the same file sets the project root: a relative
name stays under the anix home, and an absolute path is used as-is. `anix`
follows `nixos-unstable` and `home-manager` master; `amac` follows the 26.05
branches. sops-nix is pinned twice for the same reason.

## Flake inputs

| Input | Follows | Used for |
| --- | --- | --- |
| `nixpkgs` | unstable | anix |
| `nixpkgs-2605` | 26.05 | amac |
| `nixos-wsl` | `nixpkgs` | The WSL module |
| `nix-darwin` | `nixpkgs-2605` | The macOS module |
| `home-manager` | `nixpkgs` | anix home |
| `home-manager-2605` | `nixpkgs-2605` | amac home |
| `sops-nix` | `nixpkgs` | anix secrets |
| `sops-nix-2605` | `nixpkgs-2605` | amac secrets |
| `nix-homebrew` | none | Homebrew on amac |
| `herdr-src` | none | Pinned Herdr source |
| `rust-overlay` | `nixpkgs` | Herdr build |

## Paths

| Path | Host | Purpose |
| --- | --- | --- |
| `~/.config/anix` | both | Checkout. |
| `~/<projectsDir>` | anix | Project root, unless `projectsDir` is absolute. |
| `$ANIX_MAC_HOME/<name>` | amac | NFS mount of the project root; `<name>` is the last path component. |
| `/etc/nix/mac-builder` | anix | Builder private key from sops, mode `0400`. |
| `~/.config/sops/age/keys.txt` | both | Personal age key. |
| `~/.ssh/mac-builder` | anix | Builder key before sops installs it. |
| `~/.vscode/cli/token.json` | anix | Code tunnel OAuth state. |
| `~/.local/bin/apw` | anix | apw binary from `scripts/install-apw`. |
| `~/.local/lib/apw/libopentui.so` | anix | OpenTUI library that the apw binary loads. |
| `~/.config/apw/` | anix | apw config and `sync.env`; the timer is a systemd user unit. |
| `$XDG_DATA_HOME/apw/` | anix | Snapshot (`snapshot.bin`) and its lock. |
| `$XDG_STATE_HOME/apw/` | anix | `state.json` and native device identities under `adi/`. |
| `/run/secrets/<name>` | both | Decrypted sops secrets at runtime. |
| `~/.config/herdr` | both | Herdr config and palette. |
| `/opt/local` | amac Intel | MacPorts prefix, with the shim's `Cellar` and `opt` links. |

## Mac packages

Apple silicon takes Homebrew through `nix-homebrew`. The Intel host adds
MacPorts 2.12.7 and keeps Homebrew for casks, because MacPorts has no cask
equivalent and no ports for `ghostty`, `stats`, `macs-fan-control`, or
`visual-studio-code`.

On Intel, `brew` is a shim (`pkgs/brew-shim`) that speaks to `port`:

| `brew` | Intel |
| --- | --- |
| `brew --prefix` | `/opt/local` |
| `brew --prefix jq` | `/opt/local/opt/jq` |
| `brew install jq` | `sudo port -b install jq`, Homebrew when no archive exists |
| `brew list` | ports and Homebrew formulae |
| `brew install --cask stats` | the real Homebrew at `/usr/local/bin/brew` |
| `tap`, `untap`, `bundle`, `pin`, `unpin` | the real Homebrew at `/usr/local/bin/brew` |
| `switch` | refused |

Activation gives every installed port a `/opt/local/Cellar/<name>/<version>`
directory whose entries (`bin`, `lib`, `include`, `share`, `etc`) link into the
prefix, plus `/opt/local/opt/<name>` pointing at that directory. The tree never
links to the prefix itself, so scanning one formula cannot walk every port.
Until the layout has run for a port, `brew --prefix <name>` still prints
`/opt/local/opt/<name>`; the link appears on the next activation.

## Ports

| Port | From | To | Use |
| --- | --- | --- | --- |
| 22 | anix | amac | Remote builds and the Mac bootstrap. |
| 22 | Rootshel device | anix | tssh bootstrap; key authentication, Tailscale range only. |
| 2049 | amac | Windows Tailscale node | NFSv4.1, forwarded to the WSL host. |
| 443 | anix | Microsoft | Outbound code tunnel. |
| 61000-61999/udp | Rootshel device | anix | tssh session transport; control mode needs it. |

The anix firewall accepts NFS from `100.64.0.0/10`, the Tailscale range. The
code tunnel needs no inbound rule.

## Commands

| Command | What it does |
| --- | --- |
| `scripts/install [REPO_URL]` | Install Nix, clone the fork, create keys and secrets, then run the host install. |
| `scripts/bootstrap-windows.ps1` | Install WSL and NixOS-WSL from Windows, then run the anix bootstrap. |
| `scripts/rebuild [anix\|amac]` | Switch the named host; with no target, pick from the OS. |
| `scripts/check.sh` | Evaluate all hosts, parse the Windows helper with pwsh, run the activation, Rust, Node, and apw checks, then shellcheck and typos. |
| `scripts/smoke [anix\|amac]` | Read-only checks for the live host: services, secrets, SSH, brew/MacPorts, and the NFS mount. |
| `scripts/provision` | Replace an Ubuntu WSL with NixOS-WSL, transfer data, bootstrap both hosts. |
| `scripts/bootstrap --prepare` | Create keys and secrets on any host, without switching. |
| `scripts/bootstrap --host anix` | Finish the anix side and switch. |
| `scripts/bootstrap-mac-remote` | Prepare the Mac over SSH and start its first switch. |
| `sudo scripts/mount-src` | Mount the NFS export on the Mac. |
| `scripts/ios <project> <scheme> <udid>` | Build an iOS app on the Mac and install it; `--build-only` skips the device. |
| `scripts/install-herdr-plugins.sh` | Link the first-party sidebar plugin and list the set. |
| `scripts/herdr-ide` | Build the sidebar, agent, and ttt layout. Bound to `prefix+i`. |
| `scripts/herdr-action <action>` | Run `ide`, `bar`, `sidebar`, or `ttt` from a Rootshel profile shortcut. |
| `scripts/ttt-handoff vscode <path> [line] [col]` | Open a file in VS Code through the tunnel. |
| `scripts/migrate-projects.sh` | Move projects into the configured root and leave symlinks. |
| `scripts/install-apw` | Build apw and install the executable and its OpenTUI library; Linux only. |
| `scripts/apw <command>` | Apple Passwords adapter: `available`, `version`, `secret`, `backup check`. |

`scripts/apw` accepts `APW_MODE=auto|off|required`, `APW_BIN`, and
`ANIX_APW_SECRET` (default `anix-sops-age-key`). It exits `0` on success, `1`
on a verify mismatch, `2` on a usage or invalid request, `3` when the login is
absent, and `5` when apw or its snapshot is unavailable. `apw` itself reads
`APW_PASSPHRASE`; with no `APW_ANISETTE_URL` or `anisette_url`, it provisions
the device identity in `$XDG_STATE_HOME/apw/adi/`. On anix, `--prepare` imports
the passphrase and an optional external server URL from
`~/.config/apw/sync.env`. `scripts/install-apw` takes `--path DIR` to build a
local checkout and `--force` to replace an existing install.

`scripts/install` takes `--anix-user`, `--mac-user`, `--yes`, `--dry-run`,
`--no-pull`, and `--ensure-nix`. `scripts/provision`, `scripts/bootstrap`, and
`scripts/bootstrap-mac-remote` accept `--dry-run`. `scripts/provision` also
takes `--anix-user`, `--mac-user`, `--distro`, `--projects-dir`, `--backup`,
`--dir`, `--no-mac`, `--no-transfer`, `--skip-backup`, and `--yes`.
`scripts/bootstrap` also takes `--host`, `--no-switch`, `--no-install`,
`--force-ssh`, `--prepare`, and `--repo`. Most scripts print `--help`;
`scripts/ttt-handoff` takes its arguments directly.

`scripts/install`, `scripts/provision`, and `scripts/bootstrap` install Nix
with the upstream installer when it is missing. `scripts/bootstrap
--no-install` is the exception.

`scripts/provision` also takes `--mac-host`, `--image-url`, `--image-sha`, and
`--no-finalize`. `scripts/bootstrap-mac-remote` takes `--mac-host`,
`--mac-user`, `--anix-user`, `--no-first-switch`, `--yes`, and `--dry-run`.
The NixOS NFS export and `scripts/rebuild` use the fixed names `anix` and
`amac`; `--mac-host` changes only the Mac SSH target.

## Versions

| Piece | Version |
| --- | --- |
| NixOS-WSL image | 2605.7.2, SHA-256 `e7180ad555fdcb8e1e057e2ef056de467603a5e502ff8531053738371be3f6b9` |
| Herdr | 0.9.5, rootshell channel 0.1.10 |
| tsshd | 0.1.10, rootshell fork at `269df07a` |
| ttt | 1.11.0 |
| fff-mcp | 0.11.0 |
| VS Code CLI | 1.145.2 |
| Nuvio | 0.1.35-alpha |
| Xcode | 26.6 |

The Herdr fork is `kitknox/herdr` at tag `rootshell-v0.1.10`, commit
`174c202`. The sidebar plugin is `alexarthurs/herdr-sidebar` at `081ed13`.
`tsshd` is `kitknox/tsshd-rootshell` at commit `269df07a`; the Ubuntu PPA
build is protocol 1 and does not support Herdr's control stream.

## macOS host

The Mac is a build appliance. nix-darwin declares the amac user with uid 501
and `/Users/<amac>` but does not create it: the account comes from Setup
Assistant. If the short name differs from `users.nix`, the build targets a home
that does not exist.

OpenSSH is enabled with key authentication only. The builder public key is
appended to the user's `authorized_keys` by Home Manager, without replacing
keys that already exist.

Homebrew installs `ghostty`, `macs-fan-control`, `stats`, and
`visual-studio-code`, plus `xcodes` as a brew. VS Code extensions come from
`home/default/editors/extensions.txt`.

Power settings run from an activation script, so a macOS update that resets
them is repaired by the next rebuild:

```sh
pmset -a disablesleep 1 sleep 0 hibernatemode 0 standby 0 autopoweroff 0 \
  womp 1 autorestart 1
```

Auto-login reads `/run/secrets/mac-login-password` in a post-activation step
ordered after sops, then calls `sysadminctl -autologin set`. It needs FileVault
off; an encrypted volume cannot auto-login.

### Defaults

| Area | Values | Why |
| --- | --- | --- |
| Dock | Autohide, 40 px, scale effect, no launch animation, no recent apps | Keep the screen for the editor; the dock is a launcher, not a status area. |
| Finder | No desktop icons, path bar, status bar, folders first, all extensions | Files arrive over NFS; the path bar and extensions remove guesswork. |
| Global UI | Window animations off, resize time 0.001, fast key repeat, menu bar hidden | The desktop is meant to be quiet, and older Intel GPUs have less headroom. |
| Window manager | Hide widgets, hide desktop icons | The desktop should not imply that project files live on the Mac. |
| Login window | Guest off, auto-login as the amac user | The Mac must return after a reboot with nobody in front of it. |
| Trackpad | Tap to click, drag, secondary click | The laptop works without hand-tuning settings first. |
| SSH | Key authentication only, no password or keyboard-interactive | The builder key is the only remote path. |

## Limits

- nixpkgs 26.05 is the last release that builds `x86_64-darwin`. An Intel Mac
  stops receiving Nix security updates on 2026-12-31.
- Apple silicon has no such limit and is the long-term path.
- `projectsDir` is normalized. An absolute root must be under the anix home or
  `/mnt/<name>` and must already exist; Windows drive mounts and `/mnt/wsl` are
  rejected. Every segment is checked: hidden names, protected home names such
  as `Documents` and `Library`, the anix home itself, and `.` or `..` are
  rejected so the export and the Mac mount cannot cover a key directory or a
  system folder.
- FileVault stays off so the Mac can auto-login and accept SSH after a reboot.
  Anyone with physical access can read its keys.
- File watchers on the Mac do not see changes made on anix over NFS reliably.
  Keep build outputs local.
- The Windows install, the Mac TCC prompts, and the first `darwin-rebuild` run
  on real hardware only. The scripts dry-run and evaluate, but those paths are
  not covered by CI.
