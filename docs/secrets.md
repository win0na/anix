# Secrets

anix stores secrets with sops and age. The ciphertext lives in the repository;
the keys live outside it. Each host decrypts at activation with its SSH host
key, so the personal key is only needed when you edit the file.

## Files

| File | Tracked | Purpose |
| --- | --- | --- |
| `.sops.yaml.example` | yes | The recipient schema shipped with the template. |
| `.sops.yaml` | no | Your local recipient list, copied from the example by `--prepare`. |
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

`scripts/bootstrap --prepare` creates the personal key, the builder key,
`.sops.yaml`, and `secrets/secrets.yaml`, then stages the encrypted file. The
host bootstraps add each host key as a recipient:

- `scripts/bootstrap --host anix` adds `anix`.
- `scripts/bootstrap-mac-remote` adds `amac`.

The recovery key is optional. Prepare offers to generate it and add it as a
recipient; keep the private half offline.

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
SOPS_AGE_KEY_FILE=~/recovery-keys.txt sops -d secrets/secrets.yaml
```

If the personal key is lost, generate a new one, replace the `personal`
recipient in `.sops.yaml`, run `sops updatekeys`, and rebuild. If a host key is
lost, regenerate it with `sudo ssh-keygen -A`, add the new recipient, and
rebuild that host.

## Security notes

- FileVault is off on the Mac so auto-login works. Anyone with physical access
  can read its keys. Treat the Mac as an appliance on a trusted tailnet.
- The personal key is a bearer credential. The password manager copy is a
  backup, not a runtime dependency.
- `scripts/apw` is a stub for the Passwords.app adapter. Storage commands exit
  `5`; anix never calls it.
