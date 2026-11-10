# Decisions

Each entry records a choice that shapes the repository. The date is when the
choice was made, not a freshness date.

## D1: Two hosts, one repository

**Decision.** `anix` is a NixOS-WSL host on `x86_64-linux`. `amac` is a
nix-darwin host on `x86_64-darwin`. Both use the user `winona` and the
hostnames `anix` and `amac`.

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

**Consequence.** `home/winona` is imported by both hosts. A package that only
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

**Decision.** The WSL host exports `~/src` over NFSv4.1. The Mac mounts it at
`/Users/winona/src`. There is no SMB fallback.

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

**Consequence.** A FIDO2 passkey cannot be an age recipient; `ssh-to-age` and
age reject `sk-ecdsa-sha2-nistp256`. On macOS, the `sops` CLI needs
`SOPS_AGE_KEY_FILE` to use the shared path. `neededForUsers` has no effect on
macOS.

## D7: The Mac builds as winona

**Decision.** The remote builder logs in as `winona`. `winona` is in
`nix.settings.trusted-users` and has NOPASSWD sudo for `darwin-rebuild` and
`nix`.

**Why.** One user, one home, one SSH identity. A separate builder account adds
a second key, a second home, and a second permission model.

**Consequence.** `winona` is root-equivalent on the Mac. This overrides the
oracle recommendation for a dedicated builder user. The risk is accepted for a
single-user build appliance on a tailnet.

## D8: Cachix

**Decision.** Use a Cachix cache named `anix`. The token is a sops secret. The
public key is added to both hosts when the cache exists.

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
patches: `herdr-hide-tab-bar-only.patch` and `herdr-palette-fallback.patch`.
Build with `HERDR_BUILD_CHANNEL=rootshell` and `HERDR_BUILD_ID=0.1.10`.

**Why.** The fork is the base. The patches add a palette setting and a hidden
tab bar, two core features that plugins cannot provide. Everything else stays
in plugins.

**Consequence.** Each new rootshell tag needs the patches rebased. The two
patches are the only core divergence.

## D12: VSCode-shaped layout with one ttt pane

**Decision.** The left pane toggles Explorer and Source Control. The center
pane runs the agent or terminal. The bottom pane runs ttt at 35 percent. Each
workspace has one ttt instance. A patched `herdr-sidebar` opens files in that
pane and focuses it.

**Why.** The layout matches the editor the user already knows. One ttt instance
avoids a tab per file. Focusing the pane after the open keeps the keyboard on
the file.

**Consequence.** The patch must spawn `ttt <file>` with the workspace `TMPDIR`
and then call `pane.focus`. `pane.send_input` would type into the ttt TUI. The
patch is not shipped in this skeleton.

## D13: ttt settings

**Decision.** ttt uses Catppuccin mocha, `reuseWindow`, `focusOnOpen`,
`formatOnSave`, and LSP for Rust, TypeScript and JavaScript, Go, Swift, Nix,
Python, and Markdown. Markdown uses `marksman`.

**Why.** These are the languages in the active projects. ttt has no debug
adapter, no VSIX, and no per-root LSP instances; the config stays within what
ttt supports.

**Consequence.** Debugging and extension-heavy work stays in Xcode or a terminal
debugger.

## D14: Shared OpenCode, latest plugins

**Decision.** One OpenCode config on both hosts. Caveman and Moshi are removed.
`opencode-dcp-fix` is vendored. npm plugins follow latest.

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

**Why.** The first NixOS-WSL switch creates `winona` before the age key and the
encrypted file are ready. A guard avoids a chicken-and-egg failure.

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

## Open values

These values are filled at bootstrap. They are not design decisions.

| Value | Where |
| --- | --- |
| `WINDOWS_TAILSCALE_HOST` | Windows Tailscale node name |
| `MAC_TAILSCALE_IP` | Mac `100.x` address |
| `AGE_RECIPIENT_ANIX` | anix SSH host key, converted with `ssh-to-age` |
| `AGE_RECIPIENT_AMAC` | amac SSH host key, converted with `ssh-to-age` |
| `AGE_RECIPIENT_WINONA` | personal X25519 age key |
| `AGE_RECIPIENT_RECOVERY` | offline recovery key |
| Cachix public key | `anix.cachix.org-1:...` |
| Apple ID and team | Xcode signing |
| Mac login password | `mac-login-password` secret |
| Windows username | `.wslconfig` path |
| Tailnet name | Tailscale admin console |

The `apw` Linux port is a separate project. It is not a dependency of anix.
