# Troubleshooting

## NFS mount times out

`scripts/mount-src` waits 60 seconds for Tailscale and port 2049, then exits.

Check, in order:

1. Tailscale is up on Windows and the Mac.
2. The Hyper-V firewall rule allows TCP 2049 from the Mac.
3. The anix firewall allows 2049 from `100.64.0.0/10`.
4. The export names `amac`, not a stale client.
5. `wsl -d NixOS` is running.

Retry with `sudo ~/.config/anix/scripts/mount-src`.

## NFS permission denied

```sh
ls -ld /home/<anix>/src
```

If the owner is `root`, an older generation created it before the tmpfiles
rule existed. Fix it once and rebuild:

```sh
sudo chown -R <anix>:users /home/<anix>/src
```

The export squashes every client to uid 1000 on anix, so files written from the
Mac keep the same owner.

## NFS mount hangs

A dead server leaves a stale mount. Force it off on the Mac:

```sh
sudo umount -f /Users/<amac>/src
```

Then start anix and run `mount-src` again.

## Remote build fails

From anix:

```sh
ssh amac uname -m
```

If that fails, the Mac is down, Remote Login is off, or the builder key is not
in `authorized_keys`. If SSH works but Nix cannot use the builder:

```sh
sudo ssh-keyscan -t ed25519 amac >> /etc/ssh/ssh_known_hosts
ls -l /etc/nix/mac-builder
```

`/etc/nix/mac-builder` comes from the `mac-builder-key` secret. If it is
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
tailscale status
```

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

Nuvio is an unsigned Intel alpha. A Nix-installed copy has no quarantine
attribute. A manually downloaded copy needs:

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
