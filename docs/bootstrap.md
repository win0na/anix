# Bootstrap

This tutorial takes a Windows 11 machine with an Intel Mac and leaves two hosts
on one flake: `anix` on NixOS-WSL and `amac` on nix-darwin. It assumes the
configuration in this repository is complete. The host configuration is in
place; the first switch still needs the one-time steps below.

## Before you start

You need:

- Windows 11 22H2 or later, with WSL 2.4.4 or later.
- An Intel MacBookPro16,1 on macOS 26.2 or later.
- Tailscale installed on Windows and macOS, signed in to the same tailnet.
- A Cachix account and a cache named `anix`.
- The age private key, or a place to generate it.
- Every project pushed to a remote, or copied to a local backup.

Back up the old WSL distribution before you replace it. `wsl --export Ubuntu
D:\backup\ubuntu.tar` gives you a rollback.

## Part 1: Prepare Windows

1. Update WSL:

   ```powershell
   wsl --update
   wsl --version
   ```

   The version is 2.4.4 or later. `wsl --install -d NixOS` is not supported;
   use the image file in Part 2.

2. Install Tailscale on Windows and sign in. The Windows node is named `anix`;
   note its `100.x` address:

   ```powershell
   tailscale status
   tailscale ip -4
   ```

   The `100.x` address is the NFS server address for the Mac.

3. Create `%UserProfile%\.wslconfig`:

   ```ini
   [wsl2]
   memory=16GB
   processors=8
   swap=8GB
   networkingMode=mirrored
   dnsTunneling=true
   autoProxy=true

   [general]
   instanceIdleTimeout=-1

   [experimental]
   autoMemoryReclaim=gradual
   sparseVhd=true
   ```

4. Shut down WSL so the settings apply:

   ```powershell
   wsl --shutdown
   ```

5. Allow inbound TCP 2049 from the tailnet. The NFS export itself is scoped to
   `amac`. Run this in an elevated PowerShell, after confirming the WSL creator
   GUID:

   ```powershell
   Get-NetFirewallHyperVVMCreator

   New-NetFirewallHyperVRule `
     -Name "WSL-nfsd-2049" `
     -DisplayName "WSL nfsd TCP 2049" `
     -Direction Inbound `
     -Action Allow `
     -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" `
     -Protocol TCP `
     -LocalPorts 2049
   ```

   A normal `New-NetFirewallRule` does not open the WSL VM. If the rule is not
   enough, check the Tailscale interface profile and add `-Profiles Any`.

## Part 2: Install NixOS-WSL

1. Download the 26.05 image from the NixOS-WSL release page. The 2605.7.2
   asset is `nixos.wsl`:

   ```powershell
   curl.exe -L -o nixos.wsl https://github.com/nix-community/NixOS-WSL/releases/download/2605.7.2/nixos.wsl
   ```

2. Install the image:

   ```powershell
   wsl --install --from-file .\nixos.wsl
   ```

   This registers a distribution named `NixOS`.

3. Start it:

   ```powershell
   wsl -d NixOS
   ```

   The first user is `nixos`. It has passwordless sudo.

4. Clone the repository and run the first switch as `nixos`:

   ```sh
   nix shell nixpkgs#git -c git clone https://github.com/win0na/anix.git /tmp/anix
   sudo nixos-rebuild switch --flake /tmp/anix#anix
   ```

   The host configuration creates `winona`, sets it as the WSL default user,
   and enables the NFS server. The sops module stays off until
   `secrets/secrets.yaml` exists, so this switch does not need the age key.

5. Restart WSL from Windows and confirm the user:

   ```powershell
   wsl --shutdown
   wsl -d NixOS
   ```

   ```sh
   whoami
   # winona
   ```

   Keep the host running: create a logon task so WSL starts when Windows logs
   in. Run this in an elevated PowerShell:

   ```powershell
   schtasks /Create /SC ONLOGON /TN "anix-wsl" /TR "wsl.exe -d NixOS -u winona --exec /bin/true" /RL HIGHEST /F
   ```

   The task runs at logon. Enable Windows auto-login if the machine reboots
   without a person present.

6. Clone the repository as `winona`, then generate and commit the lockfile so
   both hosts resolve the same inputs:

   ```sh
   mkdir -p ~/src
   git clone https://github.com/win0na/anix.git ~/src/anix
   cd ~/src/anix
   nix flake lock
   git add flake.lock
   git commit -m "flake: lock inputs"
   git push
   ```

## Part 3: Create the secrets

1. Create the personal age key, or restore it from Passwords.app:

   ```sh
   mkdir -p ~/.config/sops/age
   nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt
   ```

   Store the private key in Passwords.app and keep the recovery key offline.

2. Add the anix host key as a recipient. The first switch generated it with
   `services.openssh.generateHostKeys`; sshd is not running. If the file is
   missing, run `sudo ssh-keygen -A` and restart WSL:

   ```sh
   nix shell nixpkgs#ssh-to-age -c ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
   ```

3. Fill `.sops.yaml` with the anix host key, the personal key, and the
   recovery key. The `amac` anchor and `*amac` entry are commented out in the
   skeleton; leave them for Part 5.

4. Create the encrypted file and add the secrets:

   ```sh
   cd ~/src/anix
   sops secrets/secrets.yaml
   ```

   Add `cachix-token`, `mac-builder-key`, and `mac-login-password`. Generate
   the builder key first:

   ```sh
   ssh-keygen -t ed25519 -C anix-builder -f ~/.ssh/mac-builder -N ""
   ```

   Add the private key as `mac-builder-key`. Keep the public key for the Mac
   host config; Home Manager installs it in `winona`'s
   `~/.ssh/authorized_keys`. The [Secrets](secrets.md) page lists the keys.

   Commit the encrypted file before the next switch. A flake only sees tracked
   files, so an untracked `secrets/secrets.yaml` keeps the sops guard off:

   ```sh
   git add .sops.yaml secrets/secrets.yaml
   git commit -m "secrets: add encrypted secrets"
   ```

5. Switch again. The sops module now sees the file and decrypts at activation:

   ```sh
   ~/src/anix/scripts/bootstrap-wsl.sh
   ```

   The script checks the environment, uses the existing checkout, warns when
   the personal key is missing, and runs `nixos-rebuild switch`.

## Part 4: Move projects

Copy the working trees you kept from the old distribution into
`/home/winona`, one directory per project. Then move them into `~/src` and
leave symlinks at the old paths:

```sh
cd ~/src/anix
scripts/migrate-projects.sh glasshelf imc isim rootshell shadPS4
```

The script refuses `anix` because the repository must stay in place while it
runs. It uses a dry run first:

```sh
scripts/migrate-projects.sh --dry-run glasshelf imc
```

Projects that exist only on a remote can be cloned directly into `~/src`; the
script is for directories that already exist in the home directory.

## Part 5: Prepare the Mac

1. Update macOS to 26.2 or later. Xcode 26.6 requires it.

2. Install the command line tools:

   ```sh
   xcode-select --install
   ```

3. Generate the SSH host keys and get the Mac recipient:

   ```sh
   sudo ssh-keygen -A
   ```

   Install Nix with the upstream daemon installer before you can run
   `ssh-to-age`:

   ```sh
   curl -L https://nixos.org/nix/install | sh -s -- --daemon
   ```

   Open a new shell, then:

   ```sh
   nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age -c ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
   ```

4. On the WSL host, uncomment the `amac` anchor and `*amac` entry in
   `.sops.yaml`, replace the placeholder with the Mac recipient, then
   re-encrypt and push:

   ```sh
   sops updatekeys secrets/secrets.yaml
   git add .sops.yaml secrets/secrets.yaml
   git commit -m "secrets: add amac recipient"
   git push
   ```

5. On the Mac, create the personal key path and copy the key from
   Passwords.app:

   ```sh
   mkdir -p ~/.config/sops/age
   # Copy the key from Passwords.app to ~/.config/sops/age/keys.txt, then:
   chmod 600 ~/.config/sops/age/keys.txt
   ```

   The personal key is for editing secrets; activation uses the Mac host key.
   The Mac's `anix` resolves to the Windows node, so an SSH copy would need a
   separate port proxy. Use Passwords.app instead.

6. Clone the repository and run the first switch from a GUI Terminal:

   ```sh
   git clone https://github.com/win0na/anix.git ~/.config/anix
   ~/.config/anix/scripts/bootstrap-mac.sh
   ```

   On the first run, the script moves the installer's `/etc/nix/nix.conf`,
   `/etc/bashrc`, and `/etc/zshrc` aside, then uses
   `nix run github:LnL7/nix-darwin/nix-darwin-26.05#darwin-rebuild` because
   `darwin-rebuild` is not installed yet. Approve the App Management prompt for
   `/Applications/Nix Apps`. A switch over SSH can fail at this step.

## Part 6: Connect the hosts

1. On the Mac, confirm the NFS mount:

   ```sh
   mount | grep /Users/winona/src
   ```

   If it is missing, run:

   ```sh
   sudo ~/.config/anix/scripts/mount-src
   ```

2. On the WSL host, confirm SSH to the Mac:

   ```sh
   ssh amac true
   ```

3. Add the Mac builder key. The host configuration installs the private key on
   WSL and the public key on the Mac. Test a Darwin build from WSL:

   ```sh
   nix build --system x86_64-darwin nixpkgs#hello --no-link
   ```

4. Rebuild both hosts through the dispatcher:

   ```sh
   scripts/rebuild anix
   scripts/rebuild amac
   ```

## Part 7: Verify

Run the repository check on WSL:

```sh
~/src/anix/scripts/check.sh
```

Then check the pieces that the script cannot:

```sh
# WSL
getent hosts amac
ssh amac uname -m
mount | grep /Users/winona/src

# Mac
pmset -g | grep -E 'disablesleep|autorestart'
xcodebuild -version
herdr plugin list
```

`ssh amac uname -m` prints `x86_64`. `herdr plugin list` shows the four pinned
plugins.

## Next steps

- Read [Networking](networking.md) before you change the NFS or Tailscale setup.
- Read [Herdr](herdr.md) before you change the layout.
- Read [Troubleshooting](troubleshooting.md) when a mount or a switch fails.
