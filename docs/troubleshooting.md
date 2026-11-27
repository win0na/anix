# Troubleshooting

## Install stops before the first switch

`scripts/install` reruns safely. It installs Nix only when it is missing and
pulls an existing checkout only when it is clean.

- If it cloned the template, run `gh repo fork --remote` in the checkout, or
  point `origin` at your fork with `git remote set-url`.
- If `sudo` or the network fails during the Nix install, fix that and run
  `scripts/install --ensure-nix`.
- If the Windows helper installed WSL, reboot Windows and run the same block
  again.

The manual prompts are listed in [Install](install.md#manual-steps).

## The Windows helper fails

The elevated helper writes a transcript to
`%TEMP%\anix\anix-bootstrap-windows.log` on Windows. When the installer reports
that the helper failed, read that file, fix the item, and rerun the same
command. The helper is idempotent; it skips an existing distribution and the
first switch when the anix user already exists.

## MacPorts package install fails

Activation prints `macports: pkg install failed` with the exact `sudo installer`
command. Run it in Terminal, then rerun `scripts/rebuild amac`. The package
postinstall runs `port selfupdate`, which needs network access and can take
several minutes.

A warning about `port sync` means the index is stale, not that the switch
failed. Run `sudo port sync` when you have network access.

## brew cannot find Homebrew

On Intel, `brew` is the shim that maps to MacPorts. `brew --caskroom` and every
`--cask` command call the real Homebrew at `/usr/local/bin/brew`. If that file
is missing, install Homebrew or use `port` for the package.

## NFS export does not start

The 6.6 WSL kernel builds `nfsd` and the `nft_ct`/`nft_fib` helpers as modules,
and NixOS-WSL does not load modules by itself. `.wslconfig` asks WSL to load
them, but only when the WSL VM starts.

Check on anix:

```sh
systemctl status nfs-server
grep -w nfsd /proc/filesystems
```

If `nfsd` is missing, restart WSL from Windows PowerShell and start the
distribution again:

```powershell
wsl --shutdown
wsl -d NixOS
```

Then confirm the module is there and rebuild:

```sh
grep -w nfsd /proc/filesystems
scripts/rebuild anix
```

A rebuild that reports failed units but exits 4 still applied the
configuration; the bootstrap treats that as a warning and prints the failed
unit names.

## NFS mount times out

`scripts/mount-src` waits 60 seconds for Tailscale and port 2049, then exits.

Check, in order:

1. Tailscale is up on Windows and the Mac.
2. The Hyper-V firewall rule allows TCP 2049 from the Mac.
3. The anix firewall allows 2049 from `100.64.0.0/10`.
4. The export names `amac`, not a stale client.
5. `wsl -d NixOS` is running.
6. `nfs-server` is active, and `grep -w nfsd /proc/filesystems` lists it.

Retry with `sudo ~/.config/anix/scripts/mount-src`.

## NFS permission denied

On anix, check the export path and its owner:

```sh
ls -ld "$ANIX_SRC_ROOT"
```

If the owner is `root`, an older generation created it before the tmpfiles
rule existed. Fix it once on anix and rebuild:

```sh
sudo chown -R "$(id -un)":users "$ANIX_SRC_ROOT"
```

The export squashes every client to uid 1000 on anix, so files written from the
Mac keep the same owner.

## NFS mount hangs

A dead server leaves a stale mount. Force it off on the Mac:

```sh
sudo umount -f "$ANIX_SRC_ROOT"
```

Then start anix and run `mount-src` again.

## Remote build fails

From anix:

```sh
ssh amac uname -m
```

It prints `arm64` on Apple silicon or `x86_64` on Intel. If the command fails,
the Mac is down, Remote Login is off, or the builder key is not in
`authorized_keys`. If SSH works but Nix cannot use the builder:

```sh
sudo ssh -i /etc/nix/mac-builder -o StrictHostKeyChecking=accept-new "$ANIX_MAC_USER@amac" true
sudo ls -l /etc/nix/mac-builder
```

The first command records the Mac host key in root's `known_hosts` and tests
the builder key. `scripts/bootstrap-mac-remote` normally does it after the
first switch. `/etc/nix/mac-builder` comes from the `mac-builder-key`
secret. If it is
missing, sops did not activate; check that the amac host key is a recipient in
`.sops.yaml`.

## First Mac switch fails

Read the log on the Mac:

```sh
less ~/anix-first-switch/first-switch.log
```

The common causes:

- The switch ran over SSH. Run `first-switch.command` from Terminal.app.
- App Management blocked Terminal. Approve it in System Settings > Privacy &
  Security > App Management.
- `/etc/nix/nix.conf`, `/etc/bashrc`, or `/etc/zshrc` already exist and
  nix-darwin refuses them. The command moves them to `*.before-nix-darwin`.

## Auto-login does not work

Check that the secret exists:

```sh
sudo test -s /run/secrets/mac-login-password && echo present
```

If it is empty, add it with `sops secrets/secrets.yaml` and rebuild amac. If it
is present, confirm FileVault is off; auto-login cannot unlock an encrypted
volume.

## The lid closes and the Mac sleeps

```sh
pmset -g | grep -E 'disablesleep|sleep'
```

Rebuild amac. Activation runs `pmset -a disablesleep 1 sleep 0 ...`; a macOS
update can reset the setting.

## WSL has no DNS

With mirrored networking, the WSL resolver follows Windows. Check:

```sh
cat /etc/resolv.conf
```

```powershell
tailscale status
```

Run `tailscale status` in Windows PowerShell; anix does not install Tailscale
inside WSL.

Restart WSL after a `.wslconfig` change:

```powershell
wsl --shutdown
```

## Herdr plugin is missing

```sh
herdr plugin list
scripts/install-herdr-plugins.sh
```

Home Manager links the patched `herdr-sidebar`. If it is absent, run
`scripts/rebuild` and check the activation output. Do not install the upstream
plugin over it.

## The sidebar opens a new tab

The patched sidebar is not active. `herdr plugin list` should show the
`herdr-sidebar` path in the Nix store, not a GitHub checkout. Rebuild and rerun
`scripts/install-herdr-plugins.sh`.

## Rootshel does not use control mode

Rootshell falls back to a plain terminal when the server or the transport does
not support a control stream. Check both ends:

```sh
herdr --version    # 0.9.5-rootshell.0.1.10 or newer
printf '' | timeout 10 herdr control
```

The first JSON line carries `"terminal_control_stream":3` and a
`control_features` list with `pane_geometry`. No line, or an error, means the
Herdr build is not the rootshell fork.

Control mode also needs tssh:

```sh
tsshd --version    # trzsz sshd 0.1.10
tsshd --attachable --port 61000-61999 --kcp
```

The JSON must say `"ProtoVer":3`; the Ubuntu PPA build says 1. Mosh cannot
carry the control stream. On WSL, forward UDP 61000-61999 from Windows.

## A profile shortcut does nothing

`herdr-action` needs Herdr, `jq`, and `ttt` on the login `PATH`, or
`HERDR_BIN_PATH` set. Run it from an SSH shell to see the error:

```sh
herdr-action ide
```

For a named session, prefix the profile command with `HERDR_SESSION=<name>`.
The action targets the focused pane, so tap the pane on the device first.

## apw cannot read the snapshot

`scripts/apw backup check` exits `5` when `apw` cannot open the snapshot. Run
`apw list --json` for the error; `apw status` only reads `state.json` and still
succeeds when the snapshot is missing. If it asks for a password, set
`APW_PASSPHRASE` in `~/.config/apw/sync.env` or unlock Secret Service. If it
reports a network or identity error, confirm the first sign-in could reach
Apple. Remove `anisette_url` or `APW_ANISETTE_URL` to use the native identity.
Deleting `$XDG_STATE_HOME/apw/adi/` makes the next sign-in provision a new
identity, but that costs an escrow attempt, and about ten failures destroy the
recovery record. A `windows.json` there means Apple refused the macOS profile.

An exit `3` means the snapshot is readable but the `anix-sops-age-key` login is
missing. Save the key with the command the check prints.

## apw cannot start

The installed binary needs glibc, `libdbus-1`, `libgcc_s`, and `libsystemd` from
the Nix store. `scripts/install-apw` roots those paths under
`~/.local/lib/apw/deps/` and rerunning it rebuilds when the existing binary
cannot run. The binary is host-bound to those paths, so copying it to another
machine does not work.

## sops cannot decrypt

From the checkout:

```sh
sops -d secrets/secrets.yaml >/dev/null
```

If that fails, compare the host recipient with `.sops.yaml`:

```sh
nix shell nixpkgs#ssh-to-age -c ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

Add the missing recipient and run `sops updatekeys -y secrets/secrets.yaml`.

## Xcode build fails

```sh
sudo xcode-select -p
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

The path must be `/Applications/Xcode-26.6.app`, not the Command Line Tools.
Automatic signing needs an Apple ID and a team in Xcode.

## Nuvio is blocked

Nuvio is an unsigned alpha. The package selects the arm64 or x86_64 DMG. A
Nix-installed copy has no quarantine attribute. A manually downloaded copy
needs:

```sh
xattr -dr com.apple.quarantine /Applications/Nuvio.app
```

## Cachix push fails

The repository does not install the `cachix` CLI. Use it from nixpkgs:

```sh
nix shell nixpkgs#cachix -c cachix push anix
```

The token is the `cachix-token` secret. A read-only token cannot push. No
substituter is configured, so `cachix use` does not affect builds.

## Rebuild says a host is unknown

`scripts/rebuild` exits `2` when the target is not `anix` or `amac`. With no
target it picks from the OS: Linux selects anix, Darwin selects amac.
