# Bootstrap

This page takes a Windows 11 machine and an Intel Mac from a clean checkout to `anix` and `amac` on one flake. The scripts prompt for each choice. Rerun a script if a step stops; it skips work that already exists.

## Before you start

You need:

- Windows 11 22H2 or later with WSL 2.4.4 or later and Git for Windows.
- An Intel MacBookPro16,1 on macOS 26.2 or later.
- Tailscale installed on Windows and macOS, signed in to the same tailnet.
- A Cachix account with a cache named `anix`.
- The personal age key, or a backup of it.

The encrypted `secrets/secrets.yaml` is committed to the public repository. It
contains the builder private key and the provider keys, protected only by age.
Keep the personal key and the offline recovery key out of the repository.

Back up the old WSL distribution before you replace it:

```powershell
wsl --export Ubuntu D:\backup\ubuntu.tar
```

The bootstrap never unregisters the old distribution.

## 1. Prepare Windows

Open PowerShell as Administrator, clone the repository, and run the Windows script:

```powershell
git clone https://github.com/win0na/anix.git $env:USERPROFILE\anix
cd $env:USERPROFILE\anix
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-windows.ps1
```

The script updates WSL, writes `%UserProfile%\.wslconfig` with 16 GB of memory and 8 processors, opens TCP 2049 for the WSL VM, downloads the 2605.7.2 image, installs it as `NixOS`, runs the first switch, clones the repository to `~/src/anix` as `winona`, and creates the `anix-wsl` logon task that keeps WSL alive.

The first switch builds the pushed `main` without `secrets/secrets.yaml`. Push your changes before you run it. A rerun on an already configured `NixOS` distribution skips the install and the first switch.

## 2. Bootstrap anix

Open the `NixOS` distribution as `winona`. Create the key directories:

```sh
mkdir -p ~/.config/sops/age ~/.ssh
```

Copy the personal age key, the Mac builder key, and the encrypted secrets from the old Ubuntu checkout. In Windows Explorer:

- Copy `\\wsl$\Ubuntu\home\winona\.config\sops\age\keys.txt` to `\\wsl$\NixOS\home\winona\.config\sops\age\keys.txt`.
- Copy `\\wsl$\Ubuntu\home\winona\.ssh\mac-builder` to `\\wsl$\NixOS\home\winona\.ssh\mac-builder`.
- Copy `\\wsl$\Ubuntu\home\winona\anix\secrets\secrets.yaml` to `\\wsl$\NixOS\home\winona\src\anix\secrets\secrets.yaml`.

Then fix the modes:

```sh
chmod 600 ~/.config/sops/age/keys.txt ~/.ssh/mac-builder ~/src/anix/secrets/secrets.yaml
```

The public builder key is derived from the private key if it is missing. Then run:

```sh
cd ~/src/anix
./scripts/bootstrap
```

The script checks the host, the age key, the builder key, and the encrypted secrets. It adds the anix host key to `.sops.yaml`, updates the sops recipients, commits with your confirmation, and runs the switch that activates sops. It then installs the pinned Herdr plugins, sets the sidebar click state, and offers the GitHub device login for the VS Code tunnel. Open the printed URL, enter the code, and authorize the same account you use in VS Code. The token is stored at `~/.vscode/cli/token.json`. If you run with `--yes`, run the printed `code tunnel user login --provider github` later and restart the unit.

The Mac login password and the Cachix token can stay empty here. Set the password on the Mac.

## 3. Bootstrap amac

On the Mac, open **Terminal**. Restore the personal age key from Passwords.app, clone the repository, and run the script:

```sh
mkdir -p ~/.config/sops/age
# Copy keys.txt from Passwords.app to ~/.config/sops/age/keys.txt.
chmod 600 ~/.config/sops/age/keys.txt
git clone https://github.com/win0na/anix.git ~/.config/anix
~/.config/anix/scripts/bootstrap
```

The script checks macOS, the command line tools, and Nix. It generates the Mac host key, adds the amac recipient, updates the sops file, prompts for the Mac login password and the Cachix token, commits with your confirmation, and runs the first switch. The first switch must run from Terminal, not SSH, because macOS App Management writes to `/Applications/Nix Apps`.

After the switch, the script offers to mount `/Users/winona/src`, build the Darwin Herdr package, install the Herdr plugins, and install Xcode 26.6. It asks before pushing the amac recipient commit; push it so anix can pull the updated secrets.

## 4. Verify

On anix:

```sh
~/src/anix/scripts/check.sh
getent hosts amac
ssh amac uname -m
```

`ssh amac uname -m` prints `x86_64`.

On amac:

```sh
mount | grep /Users/winona/src
pmset -g | grep -E 'disablesleep|autorestart'
herdr plugin list
```

`herdr plugin list` shows the four pinned plugins. Run `herdr-ide` with `prefix+i` after a Herdr restart to build the sidebar, agent, and ttt layout.

## If a step stops

Every check prints the file or command that failed. Fix that item and rerun the script. `--dry-run` prints the actions without changing anything. `--no-switch` stops before the switch. [Troubleshooting](troubleshooting.md) covers the first switch, NFS, and Tailscale failures.

## Next

Read [Networking](networking.md) before you change the NFS or Tailscale setup, and [Herdr](herdr.md) before you change the layout.
