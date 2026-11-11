# macOS

amac is a 2019 16-inch MacBook Pro that runs headless with the lid closed. It
builds Darwin and iOS outputs, serves SSH, and plays media when the lid is open.
The desktop is deliberately small.

## Hardware and OS

| Item | Value |
| --- | --- |
| Model | MacBookPro16,1 |
| CPU | Intel x86_64 |
| OS | macOS 26 Tahoe, 26.2 or later |
| Nix system | `x86_64-darwin` |
| nix-darwin | 26.05 |
| `system.stateVersion` | `7` |
| nixpkgs | `nixos-26.05` |

macOS 26 is the last Intel macOS. nixpkgs 26.05 is the last release that builds
x86_64-darwin; support ends on 2026-12-31.

## Power

The Mac stays awake with the lid closed and restarts after a power failure.

| Setting | Value |
| --- | --- |
| `disablesleep` | `1` |
| `sleep` | `0` |
| `hibernatemode` | `0` |
| `standby` | `0` |
| `autopoweroff` | `0` |
| `womp` | `1` |
| `autorestart` | `1` |

`pmset -a disablesleep 1` is the only lid-close override. nix-darwin has no
option for it, so an activation script runs the command. A macOS update can
reset the setting; the next switch restores it.

The battery charges to the built-in limit. Macs Fan Control raises the fan curve
under sustained builds. Neither setting unlocks performance beyond the thermal
design.

## Login and SSH

FileVault is off. Auto-login signs in `winona` at boot, and SSH accepts the
automation key from the WSL host. The login password is the
`mac-login-password` secret.

The activation command runs inside the console user's GUI session:

```sh
sudo launchctl asuser "$(stat -f%u /dev/console)" \
  sysadminctl -autologin set -userName winona -password -
```

The password reaches `sysadminctl` on stdin. It does not validate the password;
a wrong value fails at the next boot. `neededForUsers` does not work on macOS,
so the command must run after sops has written the secret.

| Setting | Value |
| --- | --- |
| FileVault | Off |
| Auto-login | `winona` |
| SSH | Enabled, key authentication |
| Trusted Nix user | `winona` |
| Primary user | `winona` |

`winona` is a Nix trusted user, which is root-equivalent on the Mac. This is the
cost of building as the login user without a separate builder account.

## Software

| App | Source | Version |
| --- | --- | --- |
| Ghostty | Homebrew cask | Current |
| Stats | Homebrew cask | Current |
| Macs Fan Control | Homebrew cask | Current |
| Nuvio | Nix package | 0.1.35-alpha |
| IINA | nixpkgs 26.05 | 1.4.2 |
| Xcode | `xcodes` | 26.6 |
| Command Line Tools | Apple | Current |
| VS Code | Homebrew cask | Current |

Homebrew itself comes from `nix-homebrew`; the casks are declared in
`hosts/amac`. Xcode 26.6 is the last universal Xcode. Xcode 27 is
Apple-silicon-only. Install Xcode once with `xcodes install 26.6`, then run
`xcode-select -s`, `xcodebuild -license accept`, and
`xcodebuild -runFirstLaunch`.

Nuvio is an unsigned Intel alpha. The Nix package fetches the DMG, so the app
has no quarantine attribute. A manually downloaded copy needs
`xattr -dr com.apple.quarantine /Applications/Nuvio.app`.

## VS Code

VS Code is the official Microsoft cask. Home Manager links
`settings.json` and `keybindings.json` from `home/default/editors` to
`~/Library/Application Support/Code/User`. nix-darwin's `homebrew.vscode`
installs the extension list from `home/default/editors/extensions.txt`. The
`code` binary is `/usr/local/bin/code` on the Intel Homebrew prefix; the app
bundle path is
`/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`.

VS Code opens the anix tunnel, not the NFS copy. The Remote - Tunnels connection
runs the editor server on anix against `/home/default/src`, so file watching,
LSP, terminal, and search are local to the files. The NFS mount at
`/Users/winona/src` remains for Finder and other Mac tools. The shared settings
still exclude `target`, `node_modules`, and `result*` from watching and search.

Connect with `code --remote tunnel+anix --folder-uri
vscode-remote://tunnel+anix/home/default/src`, or open
`https://vscode.dev/tunnel/anix/home/default/src` in a browser. Both require the
same GitHub account as the tunnel and a GUI session for the desktop client.

`scripts/ttt-handoff vscode <path> [line] [col]` opens the file on the Mac
through SSH with `--reuse-window --remote tunnel+anix --folder-uri ... --goto`.
VS Code must already be running in the GUI session; start it once while the lid
is open.

## Dock

Pinned apps, in order:

1. Finder
2. Safari
3. Ghostty
4. Nuvio
5. System Settings
6. Activity Monitor

Stats and Macs Fan Control stay in the menu bar, not the Dock.

## Defaults

| Domain | Key | Value |
| --- | --- | --- |
| `com.apple.dock` | `autohide` | `true` |
| `com.apple.dock` | `tilesize` | `40` |
| `com.apple.dock` | `mineffect` | `scale` |
| `com.apple.dock` | `launchanim` | `false` |
| `com.apple.dock` | `show-recents` | `false` |
| `com.apple.finder` | `CreateDesktop` | `false` |
| `com.apple.finder` | `ShowPathbar` | `true` |
| `com.apple.finder` | `ShowStatusBar` | `true` |
| `com.apple.finder` | `_FXSortFoldersFirst` | `true` |
| `com.apple.finder` | `AppleShowAllExtensions` | `true` |
| `NSGlobalDomain` | `NSAutomaticWindowAnimationsEnabled` | `false` |
| `NSGlobalDomain` | `NSWindowResizeTime` | `0.001` |
| `NSGlobalDomain` | `KeyRepeat` | `1` |
| `NSGlobalDomain` | `InitialKeyRepeat` | `10` |
| `com.apple.universalaccess` | `reduceMotion` | `true` |
| `com.apple.universalaccess` | `reduceTransparency` | `true` |
| `com.apple.WindowManager` | `StandardHideWidgets` | `true` |
| `com.apple.WindowManager` | `StandardHideDesktopIcons` | `true` |
| `com.apple.loginwindow` | `GuestEnabled` | `false` |
| `com.apple.loginwindow` | `autoLoginUser` | `winona` |
| `com.apple.AppleMultitouchTrackpad` | `Clicking` | `true` |
| `com.apple.AppleMultitouchTrackpad` | `Dragging` | `true` |
| `com.apple.AppleMultitouchTrackpad` | `TrackpadRightClick` | `true` |

nix-darwin 26.05 has no option for hiding the login avatar, so that row is
absent. Dock `persistent-apps` replaces the whole array. Nix apps live under
`/Applications/Nix Apps`; Homebrew apps live under `/Applications`.

## Media

Nuvio plays local and remote media. IINA handles formats that Nuvio does not.
Both are the only user-facing apps on the Mac. The desktop has no widgets and no
desktop icons.

## First switch

Run the first switch from a GUI Terminal, not over SSH. macOS App Management
can block writes to `/Applications/Nix Apps` from an SSH session. The bootstrap
script moves the upstream installer's `/etc/nix/nix.conf`, `/etc/bashrc`, and
`/etc/zshrc` to `*.before-nix-darwin`, then runs
`nix run github:LnL7/nix-darwin/nix-darwin-26.05#darwin-rebuild`, because
`darwin-rebuild` is not installed yet. After the first switch approves the app,
later switches work over SSH.

## Verify

```sh
pmset -g
system_profiler SPHardwareDataType
xcodebuild -version
xcodes installed
brew list --cask
nix --version
```
