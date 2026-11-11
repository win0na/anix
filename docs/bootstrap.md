# Bootstrap

This page takes the old Ubuntu WSL distribution and a fresh Intel Mac to `anix`
on NixOS-WSL and `amac` on nix-darwin. Run one script from Ubuntu. It prompts
for every choice and keeps Ubuntu until both hosts pass.

## Before you start

You need:

- Windows 11 with WSL 3.0.5 or later.
- Tailscale signed in on Windows and macOS.
- A fresh Intel MacBookPro16,1 on macOS 26.2 or later.
- A Cachix account with a cache named `anix`.
- The personal age key at `~/.config/sops/age/keys.txt`.
- `secrets/secrets.yaml` in the checkout.

The personal age key is the only irreplaceable file. Keep a copy in
Passwords.app and an offline copy before you start. The encrypted
`secrets/secrets.yaml` is safe to commit to the public repository; the private
age key and the offline recovery key are not.

## 1. Start in Ubuntu

Run the orchestrator from the existing Ubuntu checkout:

```sh
cd ~/src/anix
./scripts/provision
```

The script checks WSL, the age key, the encrypted secrets, and the repository.
It then:

1. Writes `users.nix` if you enter new usernames.
2. Offers an Ubuntu export before changing anything.
3. Installs NixOS-WSL alongside Ubuntu through the elevated Windows helper.
4. Stages the repository without secrets, runs the first `nixos-rebuild boot`
   as `nixos`, and starts the `NixOS` distribution as the anix user.
5. Transfers the keys, the encrypted secrets, and the directories you select.
6. Runs `scripts/bootstrap --host anix` inside NixOS.
7. Calls `scripts/bootstrap-mac-remote` for the Mac.

Useful options:

```text
--anix-user NAME   --mac-user NAME   --mac-host HOST
--dir PATH        transfer an extra directory (repeatable)
--backup PATH     Windows path for the Ubuntu export
--no-transfer     skip projects and keys
--no-mac          stop after anix
--skip-backup     do not export Ubuntu
--dry-run         print the plan only
--yes             accept defaults; never unregisters Ubuntu
```

The project checklist scans the top level of `$HOME` and `$HOME/src`. Select by
number. Build outputs and caches such as `target`, `node_modules`, and
`DerivedData` are excluded.

## 2. anix finishes

`scripts/bootstrap --host anix` adds the anix host key to `.sops.yaml`, runs
`sops updatekeys`, commits the encrypted file with your confirmation, and
switches. It then offers the GitHub device login for the VS Code tunnel. The
token lives at `~/.vscode/cli/token.json`; it is not a sops secret.

The Cachix token and the Mac login password can stay empty during this phase.

## 3. Prepare the Mac

The Mac must already have:

- A local account and an internet connection.
- Tailscale signed in.
- Remote Login enabled in System Settings > Sharing.
- Terminal allowed in App Management when the first switch asks.

The remote script waits for SSH, installs Nix with one sudo prompt, copies the
repository to `~/.config/anix`, generates the Mac host key, and adds the amac
recipient to sops. It then writes
`~/anix-first-switch/first-switch.command` and opens it in the Mac's logged-in
Terminal. The Terminal runs the first `darwin-rebuild`; App Management and
Homebrew prompts happen there. The script polls for `post.ok`.

The Mac does not need the personal age key for activation. Its host key
decrypts the sops file after the amac recipient is added.

After the first switch the script verifies the architecture, the NFS mount, and
the Herdr plugin list. Xcode 26.6 still needs the Apple ID and 2FA; the script
offers `xcodes`.

## 4. Finish

When both hosts pass, the script offers to export and unregister Ubuntu. The
default is to keep it. The export is a tar archive under the Windows profile;
it contains the age key and must be protected or deleted.

Run the checks:

```sh
scripts/check.sh
ssh amac uname -m
```

`ssh amac uname -m` prints `x86_64`.

## Keys and backups

- The personal age key lives at `~/.config/sops/age/keys.txt` on anix and amac.
- Keep a secure note in Passwords.app and one offline copy. The `apw` stub
  reports that the Passwords.app CLI is unavailable on Linux; store the file
  manually until the separate apw port exists.
- The anix bootstrap offers to generate the offline recovery key, add it as a
  `recovery` recipient, and update the sops file. Choose a path on offline media
  and move the private key there.
- The encrypted `secrets/secrets.yaml` in git is the ciphertext backup. Never
  commit a decrypted copy.
- Host SSH keys are not backed up. Regenerate a lost host key and update the
  recipients with the personal or recovery key.

## If a step stops

Every phase prints the command or file that failed. Fix that item and rerun;
the provision skips completed phases. `--dry-run` prints the plan, and
`--no-mac` stops after anix. [Troubleshooting](troubleshooting.md) covers WSL,
NFS, Tailscale, and first-switch failures.

## Next

Read [Networking](networking.md) before changing NFS or Tailscale, and
[Herdr](herdr.md) before changing the layout or the ttt handoff.
