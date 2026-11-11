# Decisions

Each entry records a choice that shapes the repository.

## D1: Two hosts, one repository

**Decision.** `anix` is a NixOS-WSL host on `x86_64-linux`. `amac` is a
nix-darwin host on `x86_64-darwin`. Both use the usernames in `users.nix` and
the hostnames `anix` and `amac`.

**Why.** The two machines share one home configuration, one project tree, and
one set of editor and agent settings. A single flake keeps those in lockstep.

**Consequence.** A change that only works on one platform needs a platform
module, not a branch in a shared file.

## D2: Two nixpkgs channels

**Decision.** anix follows `nixos-unstable`. amac follows `nixos-26.05`.
Home Manager follows the matching channel on each host.

**Why.** nixpkgs 26.05 is the last release that builds and supports
x86_64-darwin. The WSL host has no such limit and benefits from unstable. Home
Manager and nix-darwin must match the nixpkgs they evaluate against.

**Consequence.** Shared modules use only options present in both Home Manager
branches. Platform-specific options stay in `modules/nixos` or
`modules/darwin`.

## D3: Integrated Home Manager

**Decision.** Both hosts enable Home Manager with `useGlobalPkgs = true` and
`useUserPackages = true`.

**Why.** One user configuration, one package set per host, and no separate
`home-manager switch` step.

**Consequence.** `home/default` is imported by both hosts. A package that only
exists on one platform is gated by the host module.

## D4: Local config clone on the Mac

**Decision.** The Mac builds from a local clone at `~/.config/anix`. The WSL
host keeps its checkout at `~/src/anix`. The WSL checkout is visible to the Mac
through the export at `/Users/winona/src/anix`, but the Mac does not build from
that copy.

**Why.** A local clone keeps `darwin-rebuild` working when the NFS mount is
down, avoids Git `dubious ownership` from the uid mapping, and prevents a
failed switch from removing the source it is building.

**Consequence.** `scripts/rebuild amac` runs `git pull --ff-only` before the
switch. A dirty checkout stops the rebuild.

## D5: NFSv4.1, no SMB

**Decision.** The WSL host exports `~/src` over NFSv4.1. The Mac mounts
`anix:/`, the Windows Tailscale node, at `/Users/winona/src`. The WSL hostname
is also `anix`. There is no SMB fallback.

**Why.** macOS has a native NFS client. NFSv4.1 needs one TCP port, maps cleanly
with `all_squash`, and avoids a second daemon and credential store.

**Consequence.** When NFS is down, `~/src` is unavailable on the Mac. The config
repository and local build artifacts still work. File watchers on the Mac do
not reliably see WSL changes.

## D6: sops-nix with age

**Decision.** Secrets use sops and age. Recipients are the anix host key, the
amac host key, a personal X25519 key, and an offline recovery key. The personal
key is copied to `~/.config/sops/age/keys.txt` on both hosts and backed up in
Passwords.app.

**Why.** Host keys let activation decrypt without the personal key on disk. The
personal key lets either host edit the file. The recovery key survives a lost
laptop or a lost host key.

The personal key was generated with `age-keygen` at
`~/.config/sops/age/keys.txt`. The builder key was generated at
`~/.ssh/mac-builder`.

**Consequence.** A FIDO2 passkey cannot be an age recipient; `ssh-to-age` and
age reject `sk-ecdsa-sha2-nistp256`. On macOS, the `sops` CLI needs
`SOPS_AGE_KEY_FILE` to use the shared path. `neededForUsers` has no effect on
macOS.

## D7: The Mac builds as the amac user

**Decision.** The remote builder logs in as the amac user. That user is in
`nix.settings.trusted-users`. The bootstrap prompts for sudo; no sudoers rule
is committed.

**Why.** The Mac is a single-user build appliance. A separate builder account
adds another key, home, and permission model.

**Consequence.** The amac user is root-equivalent on the Mac. That risk is
accepted for a single-user appliance on a tailnet.

## D8: Cachix

**Decision.** Use a Cachix cache named `anix`. The token is a sops secret. The
substituter is not configured yet; add the public key to both hosts when the
cache exists.

**Why.** The Mac cannot serve Linux paths, and the WSL host cannot build Darwin
paths. A shared binary cache covers the gap and speeds up rebuilds.

**Consequence.** Pushing needs a write token. The cache public key is an
operational value, not a design value.

## D9: Homebrew and media apps

**Decision.** Ghostty, Stats, and Macs Fan Control come from Homebrew casks
through nix-homebrew. Nuvio is a pinned Nix package. IINA comes from nixpkgs
26.05. Xcode 26.6 is installed with `xcodes`.

**Why.** Ghostty is Linux-only in nixpkgs 26.05. Nuvio ships an unsigned Intel
DMG with no nixpkgs package. Xcode 26.6 is the last universal Xcode; 27 is
Apple-silicon-only.

**Consequence.** Nuvio is an unsigned alpha and can trigger Gatekeeper. The
Nix-fetched copy has no quarantine attribute. A manually downloaded copy needs
`xattr -dr com.apple.quarantine`.

## D10: Minimal Mac desktop

**Decision.** The Dock holds Finder, Safari, Ghostty, Nuvio, System Settings,
and Activity Monitor. Desktop icons and widgets are hidden. Motion and
transparency are reduced. FileVault is off, auto-login is on, and `pmset`
disables sleep with the lid closed.

**Why.** The Mac is a headless builder. The UI exists for media and occasional
maintenance.

**Consequence.** FileVault off is a physical-security tradeoff. A macOS update
can reset `disablesleep`; the activation script restores it.

## D11: Herdr from the rootshell fork

**Decision.** Pin `github:kitknox/herdr/rootshell-v0.1.10` and apply two
patches through a Nix overlay: `herdr-hide-tab-bar-only.patch` and
`herdr-palette-fallback.patch`. Build with `HERDR_BUILD_CHANNEL=rootshell` and
`HERDR_BUILD_ID=0.1.10`.

**Why.** The fork is the base. The patches add a palette setting and a hidden
tab bar, two core features that plugins cannot provide. Everything else stays
in plugins.

**Consequence.** Each new rootshell tag needs the patches rebased. The two
patches are the accepted exception to the plugin-only goal. They stay in the
overlay until the rootshell fork accepts them.

## D12: VSCode-shaped layout with one ttt pane

**Decision.** The left pane toggles Explorer and Source Control. The center
pane runs the agent or terminal. The bottom pane runs ttt at 35 percent. Each
workspace has one ttt instance. The ttt pane carries a stable marker token. A
patched `herdr-sidebar` finds that token, spawns `ttt <file>` so the call
forwards to the running instance, then focuses the pane.

**Why.** The layout matches the editor the user already knows. One ttt instance
avoids a tab per file. Focusing the pane after the open keeps the keyboard on
the file.

**Consequence.** The patch must spawn `ttt <file>` with the workspace `TMPDIR`
and then call `pane.focus`. `pane.send_input` would type into the ttt TUI. The
marker token must survive pane recreation, so the layout action sets it on every
run. The patch is built in `pkgs/herdr-sidebar` and linked by the Home Manager
activation.

## D13: ttt settings

**Decision.** ttt uses Catppuccin mocha, `reuseWindow`, and a collapsed
sidebar. `focusOnOpen` and `formatOnSave` are off. The shared settings have no
`lsp.servers` list yet; add servers when a project needs them.

**Why.** The shared file carries only settings that exist today. ttt has no
debug adapter, no VSIX, and no per-root LSP instances.

**Consequence.** Debugging and extension-heavy work stays in Xcode or a terminal
debugger.

## D14: Shared OpenCode, latest plugins

**Decision.** One OpenCode config on both hosts. The full config lives in the
repository; skills are provisioned separately. Caveman and Moshi are removed.
`opencode-dcp-fix` is vendored. npm plugins follow latest. Provider credentials
are interactive OAuth logins stored in OpenCode's local state, not sops.

**Why.** The user wants the same agent setup on both hosts and fewer forks.
Vendoring the DCP fix keeps the local change in the repository. Latest plugins
avoid a pinning matrix.

**Consequence.** Two rebuilds can load different npm plugin code. A broken
upstream release reaches both hosts. Pin one plugin only when it breaks.

## D15: Fresh zsh

**Decision.** Both hosts use zsh with completion, autosuggestions, syntax
highlighting, and shared history settings. The bash configuration is not
migrated.

**Why.** A fresh shell is smaller than porting a 142-line bashrc. The history
settings are shared even though the history file is local to each host.

**Consequence.** Old bash aliases and functions are not carried over unless
they are added to the zsh config.

## D16: One rebuild dispatcher

**Decision.** `scripts/rebuild` detects the host or takes `anix` or `amac`.
From WSL, `scripts/rebuild amac` pulls `~/.config/anix` on the Mac and runs
`darwin-rebuild` over SSH.

**Why.** The user runs the same command from either host. The dispatcher hides
the channel and the SSH path.

**Consequence.** The Mac must be reachable at `amac` and the checkout must be
clean enough for `git pull --ff-only`.

## D17: Git-only backups

**Decision.** Projects are backed up through their Git remotes. There is no
separate backup service for `~/src`.

**Why.** The user accepted the risk. Most projects already have remotes.

**Consequence.** Unpushed work and repositories without an origin are not
backed up. The migration script leaves the old paths as symlinks, not copies.

## D18: Public MIT repository

**Decision.** The repository is public and licensed MIT. The name is `anix`.

**Why.** The configuration is reusable and has no secret material. MIT is the
least friction for a personal config.

**Consequence.** Every secret stays in sops. The age private key never enters
the repository.

## D19: sops activates when the file exists

**Decision.** The host module imports sops only when `secrets/secrets.yaml`
exists.

**Why.** The first NixOS-WSL switch creates the anix user before the age key and
the encrypted file are ready. A guard avoids a chicken-and-egg failure.

**Consequence.** Adding `secrets/secrets.yaml` enables decryption on the next
switch. The recipients must be correct before that commit.

## D20: Skills are provisioned separately

**Decision.** The OpenCode config is shared, but the two skill directories are
provisioned from their own sources rather than vendored.

**Why.** The skill trees are about 35 MB and have their own update and license
terms. Copying them into the config repository would make every skill edit a
config commit.

**Consequence.** A missing skill directory is a setup error. The config still
points at the standard paths: `~/.config/opencode/skills` and
`~/.agents/skills`.

## D21: VS Code uses the official code tunnel

**Decision.** anix runs Microsoft's official `code tunnel` as a declarative
systemd system service as the anix user. VS Code desktop on amac connects through
Remote - Tunnels; browser access is `vscode.dev`. Coder code-server, its
password, and its 8080 exposure are removed. NFS remains for Finder and other
Mac tools.

**Why.** The tunnel removes the inbound port and password, gives the Mac
desktop a real remote workspace, and keeps the GitHub account as the access
boundary. It replaces code-server's browser-only model.

**Consequence.** The CLI and server are unfree; the server downloads and
updates outside Nix, so `programs.nix-ld` is required. The token is user state
at `~/.vscode/cli/token.json`, not a sops secret. The Mac and anix must use the
same GitHub account. NFS is no longer in the VS Code path.

## Open values

These values are fixed or filled at bootstrap. They are not design decisions.

| Value | Where |
| --- | --- |
| Windows Tailscale node | `anix`; the Mac mounts `anix:/` |
| NFS client name | `amac` (MagicDNS) |
| VS Code tunnel name | `anix` |
| `AGE_RECIPIENT_ANIX` | anix SSH host key, converted with `ssh-to-age` |
| `AGE_RECIPIENT_AMAC` | amac SSH host key, converted with `ssh-to-age` |
| `AGE_RECIPIENT_PERSONAL` | personal X25519 age key |
| `AGE_RECIPIENT_RECOVERY` | offline recovery key |
| Cachix public key | `anix.cachix.org-1:...` |
| Apple ID and team | Xcode signing |
| Mac login password | `mac-login-password` secret |
| Windows username | `.wslconfig` path |
| Tailnet name | Tailscale admin console |

The `apw` Linux port is a separate project. It is not a dependency of anix.
