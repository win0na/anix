# Secrets

anix stores secrets with sops and age. The ciphertext lives in the repository;
the keys live outside it. Each host decrypts at activation with its SSH host
key, so the personal key is only needed when you edit the file.

## Files

| File | Tracked | Purpose |
| --- | --- | --- |
| `.sops.yaml.example` | yes | The recipient schema shipped with the template. |
| `.sops.yaml` | yes | Your recipient list. `--prepare` creates it from the example; it holds public keys only. |
| `secrets/secrets.yaml` | yes | The encrypted values. Commit it to your fork. |
| `~/.config/sops/age/keys.txt` | no | The personal key. Never commit it. |
| `/etc/ssh/ssh_host_ed25519_key` | no | The host key sops-nix uses at activation. |

`SOPS_AGE_KEY_FILE` is set to the same path in both home configurations, so the
sops CLI behaves the same on NixOS and macOS.

## What is stored

| Secret | Read by |
| --- | --- |
| `mac-builder-key` | The anix remote builder, installed at `/etc/nix/mac-builder`. |
| `mac-login-password` | The amac auto-login script. |
| `cachix-token` | Pushing to the `anix` cache, when you use one. |

The VS Code tunnel token is not here. It is OAuth state in
`~/.vscode/cli/token.json`, created by `code tunnel user login`.

## First setup

Both install paths run this step for you. To do it by hand, run
`scripts/bootstrap --prepare`. It creates the personal key, the builder key,
`.sops.yaml`, and `secrets/secrets.yaml`, then stages the encrypted file. The
host bootstraps add each host key as a recipient:

- `scripts/bootstrap --host anix` adds `anix`.
- `scripts/bootstrap-mac-remote` adds `amac`.

The recovery key is optional. Prepare offers to generate it and add it as a
recipient; keep the private half offline.

## Apple Passwords backup

`apw` reads an encrypted snapshot of iCloud Passwords on Linux. `scripts/apw`
wraps it for the personal age key, so the key can live in Apple Passwords, not
only in a manual copy.

On anix, `scripts/install-apw` builds apw and installs the executable; OpenTUI
is linked in, so there is no separate library. `apw` provisions the device
identity in process, so it needs no anisette server. The first sign-in needs
network access to Apple and may ask for a two-factor code and the escrow
passcode; later sign-ins reuse `$XDG_STATE_HOME/apw/adi/macos.json` (or
`windows.json` when Apple refuses the macOS profile). The [apw install docs](https://github.com/win0na/apw/blob/main/docs/install.md)
cover the identity and the build.

```sh
scripts/install-apw
apw login
apw sync
grep '^AGE-SECRET-KEY-' ~/.config/sops/age/keys.txt |
  scripts/apw secret set anix-sops-age-key --stdin
scripts/apw backup check
```

`backup check` reports whether the login exists and compares it with
`~/.config/sops/age/keys.txt` when that file is present.
`scripts/bootstrap --prepare` offers to restore a missing personal key from
Apple Passwords and to save a newly generated one. The login is named
`anix-sops-age-key`; only the `AGE-SECRET-KEY-...` line is stored.

To save an existing key by hand:

```sh
grep '^AGE-SECRET-KEY-' ~/.config/sops/age/keys.txt |
  scripts/apw secret set anix-sops-age-key --stdin
```

If you used a separate anisette service, delete `anisette_url` from
`~/.config/apw/config.toml` and `APW_ANISETTE_URL` from `sync.env`; with either
set, `apw` keeps using that server. Sign in again so the session uses the macOS
identity that the escrow flow needs.

`scripts/bootstrap --prepare` reads `~/.config/apw/sync.env` for
`APW_PASSPHRASE`, the same file the hourly timer uses. It also imports
`APW_ANISETTE_URL` when you deliberately use an external server. `APW_MODE=off`
skips Apple Passwords; `APW_MODE=required` makes `--prepare` stop when `apw`
cannot read the snapshot.

## Add a secret

1. Open the encrypted file:

   ```sh
   sops secrets/secrets.yaml
   ```

2. Add the key and save.
3. Declare it in the host module:

   ```nix
   sops.secrets."name" = { };
   ```

4. Read it from the path in `sops.secrets."name".path`.
5. Rebuild the host that reads it.

On NixOS, `neededForUsers = true` makes the secret available before a user
logs in. It has no effect on nix-darwin, which cannot manage user passwords.

## Add or replace a host recipient

Convert the host's public key:

```sh
nix shell nixpkgs#ssh-to-age -c ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

Add the result to `.sops.yaml`, then re-encrypt the data key for the new
recipient set:

```sh
sops updatekeys -y secrets/secrets.yaml
```

Commit the re-encrypted file and rebuild both hosts. Remove a recipient the
same way. `updatekeys` changes who can unwrap the data key; it does not change
the data key itself.

## Rotate

```sh
sops rotate -i secrets/secrets.yaml
sops updatekeys -y secrets/secrets.yaml
```

Commit the result and rebuild both hosts. Rotate the data key when a secret
leaks. Change recipients when a key is lost or a host is retired.

## Recover

With the offline recovery key:

```sh
SOPS_AGE_KEY_FILE=~/anix-recovery-YYYYMMDD.txt sops -d secrets/secrets.yaml
```

`--prepare` names the file `~/anix-recovery-$(date +%Y%m%d).txt` unless you
give another path.

If the key is in Apple Passwords, `scripts/bootstrap --prepare` restores it to
`~/.config/sops/age/keys.txt` when the file is missing.

If the personal key is lost, generate a new one and make it a recipient:

```sh
age-keygen -o ~/.config/sops/age/keys.txt
```

Replace the `personal` recipient in `.sops.yaml` with the new public key, then
run `sops updatekeys` with a key that can still unwrap the data key. The
recovery key works directly:

```sh
SOPS_AGE_KEY_FILE=~/anix-recovery-YYYYMMDD.txt sops updatekeys -y secrets/secrets.yaml
```

A host key works too, but it must be converted first; `SOPS_AGE_SSH_PRIVATE_KEY_FILE`
only covers native `ssh-ed25519` recipients:

```sh
SOPS_AGE_KEY=$(sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key) \
  sops updatekeys -y secrets/secrets.yaml
```

If a host key is lost, regenerate it with `sudo ssh-keygen -A`, add the new
recipient, and rebuild that host.

## Security notes

- FileVault is off on the Mac so auto-login works. Anyone with physical access
  can read its keys. Treat the Mac as an appliance on a trusted tailnet.
- The personal key is a bearer credential. The password manager copy is a
  backup, not a runtime dependency.
- `scripts/apw` is a thin adapter over [apw](https://github.com/win0na/apw).
  It stores the personal age key as the `anix-sops-age-key` login in Apple
  Passwords; only `secret get` prints it. `APW_MODE=off` disables it.
