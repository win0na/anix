# Troubleshooting

Each section starts with the symptom, then the check, then the fix. Run commands
on the host named in the heading.

## NFS mount times out

Symptom: `mount_nfs` prints `Operation timed out`, or `/Users/winona/src` is
empty.

Check the Mac can reach the server:

```sh
nc -vz anix 2049
```

Check the WSL host is listening and exporting:

```sh
sudo ss -ltnp | grep 2049
sudo exportfs -v
```

Fix:

1. Confirm Tailscale is up on Windows and the Mac.
2. Confirm the Hyper-V firewall rule allows TCP 2049 from the Mac.
3. Confirm the NixOS firewall allows 2049 from `100.64.0.0/10`.
4. Confirm the export names `amac`, not a stale client.
5. Retry with `sudo scripts/mount-src`.
6. If `mount_nfs` rejects `vers=4.1`, retry with `vers=4`.

`scripts/mount-src` waits 60 seconds for Tailscale and port 2049 before it
mounts.

## NFS server is absent after a Windows reboot

Symptom: the Mac cannot mount, and the WSL host is not running.

Check the logon task on Windows:

```powershell
schtasks /Query /TN "anix-wsl"
```

Fix: create the task if it is missing:

```powershell
schtasks /Create /SC ONLOGON /TN "anix-wsl" /TR "wsl.exe -d NixOS -u winona --exec /bin/true" /RL HIGHEST /F
```

The task runs at logon. If the machine reboots unattended, enable Windows
auto-login.

## NFS permission denied

Symptom: the mount succeeds, but reads or writes fail with `Permission denied`.

Check the export:

```sh
sudo exportfs -v
```

The export needs `all_squash,anonuid=1000,anongid=1000`. The Mac mounts with
`noowners`. Check the directory mode on WSL:

```sh
stat -c '%U %G %a' /home/winona/src
```

Fix the export options or the directory ownership. A Mac uid of 501 is squashed
to 1000; without `noowners` the client tries to enforce the wrong owner.

## NFS mount hangs

Symptom: `ls /Users/winona/src` blocks, or a build stalls on a file read.

Check the mount and the server:

```sh
mount | grep /Users/winona/src
ping -c 1 anix
```

Fix:

```sh
sudo umount -f /Users/winona/src
sudo ~/.config/anix/scripts/mount-src
```

If the WSL VM was stopped, start it on Windows and wait for `nfsd`. `hard`
mounts retry instead of failing; `intr` lets you interrupt a hung process.

## Remote build fails

Symptom: `nix build --system x86_64-darwin` builds locally or fails with an SSH
error.

Check the path from WSL:

```sh
ssh -i /etc/nix/mac-builder winona@amac true
ssh amac nix --version
```

Check the Mac trusts the user:

```sh
ssh amac 'sudo cat /etc/nix/nix.conf'
```

The file contains `trusted-users = winona`. The daemon must be running:

```sh
ssh amac 'sudo launchctl print system/org.nixos.nix-daemon'
```

Fix:

1. Confirm the private key at `/etc/nix/mac-builder` has mode `0400`.
2. Confirm the public key is in `winona`'s `authorizedKeys` on the Mac.
3. Confirm `nix.buildMachines` uses `hostName = "amac"` and `protocol =
   "ssh-ng"`.
4. Run `scripts/rebuild amac` once to apply the Mac config.

## First Mac switch fails

Symptom: `darwin-rebuild: command not found`, or nix-darwin stops with
`Unexpected files in /etc`.

A fresh Mac has no `darwin-rebuild`. The upstream installer also leaves
`/etc/nix/nix.conf`, `/etc/bashrc`, and `/etc/zshrc` behind, which nix-darwin
refuses on the first activation.

Fix: run `scripts/bootstrap`. It moves those files to
`*.before-nix-darwin` and runs:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run \
  github:LnL7/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake ~/.config/anix#amac
```

After the first switch, `darwin-rebuild` is on `PATH`.

## Mac switch fails over SSH

Symptom: `darwin-rebuild` stops while writing to `/Applications/Nix Apps`, or
macOS shows an App Management prompt.

Fix: run the first switch from a GUI Terminal on the Mac:

```sh
~/.config/anix/scripts/bootstrap
```

Approve the prompt. Later switches work over SSH. If the prompt does not appear,
open System Settings > Privacy & Security > App Management and add Terminal.

## Auto-login does not work

Symptom: the Mac stops at the login window after a reboot.

Check FileVault and the setting:

```sh
fdesetup status
sudo sysadminctl -autologin status
```

FileVault must be off. Check that `/etc/kcpassword` exists and that the login
password in sops is current. The activation command must run in the console
user's GUI session:

```sh
sudo launchctl asuser "$(stat -f%u /dev/console)" \
  sysadminctl -autologin set -userName winona -password -
```

`sysadminctl` does not validate the password. A wrong value still exits 0 and
fails at the next boot. Re-enter the secret and switch again.

## Lid close still sleeps

Symptom: the Mac sleeps when the lid closes, and SSH drops.

Check:

```sh
pmset -g | grep -E 'disablesleep|sleep|hibernatemode'
```

`disablesleep` must be `1`. A macOS update can reset it. Run:

```sh
sudo pmset -a disablesleep 1 sleep 0 hibernatemode 0 standby 0 autopoweroff 0 womp 1 autorestart 1
```

Then rebuild so the activation script records the setting.

## WSL has no DNS

Symptom: `amac` does not resolve, or package downloads fail.

Check:

```sh
getent hosts amac
cat /etc/resolv.conf
```

Fix:

1. Confirm `dnsTunneling=true` in `%UserProfile%\.wslconfig`.
2. Confirm MagicDNS is enabled in the Tailscale admin console.
3. Restart WSL: `wsl --shutdown`, then start it again.
4. As a temporary fallback, use the Mac's Tailscale IP instead of `amac`.

Do not hardcode `100.100.100.100` in the NixOS config. It hides a broken tunnel.

## WSL clock drifts

Symptom: TLS errors, or `nix` complains about a timestamp in the future.

Check:

```sh
timedatectl
```

Fix: resync from Windows:

```powershell
wsl --shutdown
wsl -d NixOS
```

NixOS starts `systemd-timesyncd`; the WSL root namespace provides the clock.
A large drift after a laptop suspend usually clears on the next WSL restart.

## Herdr plugin is missing

Symptom: an action does nothing, or `herdr plugin list` does not show a plugin.

Check:

```sh
herdr plugin list
herdr plugin link /home/winona/src/anix/pkgs/herdr-plugins/responsive-sidebar
```

`herdr plugin link` registers the plugin enabled by default; `--disabled` registers it off.
The three remote plugins are installed from pinned commits:

```sh
herdr plugin install jeffarese/herdr-bar --ref d9cdd88cb734615e96b1c37ed17fc39be904f060
herdr plugin install alexarthurs/herdr-sidebar/plugins/herdr-sidebar --ref 081ed133f3faa377438b51ce435fe8a87c439593
herdr plugin install eugenioenko/ttt/herdr-plugin --ref b51ae983e0f60599090e0b0061093dbece9b541f
```

If a plugin loads but its pane is blank, check the Herdr log in the state
directory. `HERDR_PLUGIN_STATE_DIR` names the location.

## Sidebar opens a new tab

Symptom: clicking a file creates a new editor tab instead of using the ttt pane.

The editor-pane patch is not applied. Confirm the pinned `herdr-sidebar` commit
is `081ed13` and that the overlay builds the patched plugin. Until the patch
lands, the stock plugin creates one tab per unseen file.

## ttt opens in the wrong workspace

Symptom: a file opens in another workspace's ttt.

ttt forwards to the newest socket in `$TMPDIR/ttt-uid/`. The layout must give
each workspace its own `TMPDIR`, and the sidebar launcher must use the same
value. Check the launcher environment and the ttt pane environment. As a
temporary workaround, set `TTT_FORWARD_SOCKET` to the target socket.

## sops cannot decrypt

Symptom: activation fails with `no matching keys`, or `sops -d` fails.

Check the key path and the recipients:

```sh
echo "$SOPS_AGE_KEY_FILE"
sops -d secrets/secrets.yaml
nix shell nixpkgs#ssh-to-age -c ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

The host recipient must appear in `.sops.yaml` and in the encrypted
file. After adding a recipient, run `sops updatekeys secrets/secrets.yaml` and
commit the result. If activation skips sops entirely, check that the file is
tracked: `git ls-files secrets/secrets.yaml`.

On macOS, set `SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt`. The `sops`
CLI defaults to `~/Library/Application Support/sops/age/`.

## Xcode build fails

Symptom: `scripts/ios` fails before it reaches the device.

Check:

```sh
xcodebuild -version
xcode-select -p
```

Fix:

1. Accept the license: `sudo xcodebuild -license accept`.
2. Run first launch: `sudo xcodebuild -runFirstLaunch`.
3. Confirm the scheme exists: `xcodebuild -list -project PATH`.
4. Confirm the device is paired and trusted. `xcrun devicectl list devices`
   shows the identifier.
5. If signing fails over SSH, unlock the login keychain in that session with
   `security unlock-keychain ~/Library/Keychains/login.keychain-db`, or run
   the first signing build from the GUI.

The build uses a `mktemp` directory under `/tmp`, so artifacts stay off NFS.
The script passes `-allowProvisioningUpdates`; automatic signing needs the
Apple ID and team in Xcode.

## Nuvio is blocked

Symptom: macOS refuses to open Nuvio.

The Nix package fetches the DMG, so the app has no quarantine attribute. A
manually downloaded copy does:

```sh
xattr -dr com.apple.quarantine /Applications/Nuvio.app
```

Nuvio 0.1.35-alpha is unsigned. Gatekeeper can still warn on first launch.

## Cachix push fails

Symptom: `cachix push anix` returns 403.

Check the token and the cache:

```sh
cachix authtoken
cachix use anix
```

The token is the `cachix-token` secret. The public key in the Nix config must
match the cache. A token with read-only access cannot push.

## Rebuild says a host is unknown

Symptom: `scripts/rebuild` exits 2.

The target must be `anix` or `amac`. With no target, Linux selects `anix` and
Darwin selects `amac`. Run `scripts/rebuild --help` for the supported forms.
