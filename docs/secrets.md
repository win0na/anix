# Secrets

anix stores secrets with sops and age. The encrypted file lives in the
repository; the private key lives outside it. sops-nix decrypts at activation
with each host's SSH host key.

NixOS imports `sops-nix.nixosModules.sops`. nix-darwin imports
`sops-nix-2605.darwinModules.sops`. Both modules support
`sops.age.sshKeyPaths`. The Darwin default reads
`/etc/ssh/ssh_host_ed25519_key`, so the key must exist; enabling OpenSSH
generates it.

## What is stored

| Secret | Used by |
| --- | --- |
| `mac-login-password` | macOS auto-login at boot |
| `cachix-token` | Pushing to the `anix` cache |
| `mac-builder-key` | WSL to Mac SSH for remote builds |
| `opencode-api-keys` | OpenCode providers |

The VS Code tunnel token is OAuth user state in
`~/.vscode/cli/token.json`, not a sops secret. It is created by
`code tunnel user login --provider github` and is bound to the GitHub account.

Add a secret only when a host or a service reads it. The encrypted file is
`secrets/secrets.yaml`; the creation rules are in `.sops.yaml`.

## Create the personal key

The personal key is a dedicated X25519 age key. A FIDO2 passkey cannot be an
age recipient: `ssh-to-age` and age reject `sk-ecdsa-sha2-nistp256`.

On the WSL host, after the first switch:

```sh
mkdir -p ~/.config/sops/age
nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt
```

The last command prints the public recipient. Store the private key in
Passwords.app as a login item, and keep a copy of the recovery key offline. Do
not commit either key.

Copy the same private key to the Mac at `~/.config/sops/age/keys.txt` with mode
`600`. The two hosts need the same personal key to edit the same file.

The `sops` CLI on macOS looks under `~/Library/Application Support/sops/age/`
by default. Set `SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt` in the
shared zsh config so both hosts use the same path.

## Collect host keys

Each host decrypts at activation with its SSH host key. Convert the public key
to an age recipient:

```sh
nix shell nixpkgs#ssh-to-age -c ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

On the Mac, generate the host keys first if they do not exist:

```sh
sudo ssh-keygen -A
```

The result is an `age1...` recipient for each host.

## Set the recipients

Replace the placeholders in `.sops.yaml`:

```yaml
keys:
  anix: &anix age1...
  amac: &amac age1...
  winona: &winona age1...
  recovery: &recovery age1...

creation_rules:
  - path_regex: secrets/[^/]+\.yaml$
    age:
      - *anix
      - *amac
      - *winona
      - *recovery
```

`anix` and `amac` are the host keys. `winona` is the personal key. `recovery` is
the offline key. The personal key lets you edit from either host; the host keys
let sops-nix decrypt at boot without the personal key on disk.

## Create the encrypted file

From the repository root:

```sh
sops secrets/secrets.yaml
```

Add each key from the table. Save and exit. Check the result:

```sh
sops -d secrets/secrets.yaml
```

The decrypted output is plaintext. Do not redirect it to a file inside the
repository.

## Enable sops

The host module imports sops-nix only when `secrets/secrets.yaml` exists. That
guard lets the first switch run before the key and the encrypted file are ready.
After the file exists, the next switch enables decryption.

A flake only sees tracked files. Commit `secrets/secrets.yaml` and `.sops.yaml`
before the switch, or the guard stays off and activation skips sops.

The host configuration sets:

```nix
sops.defaultSopsFile = ../secrets/secrets.yaml;
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
sops.secrets."mac-login-password" = { };
```

`sshKeyPaths` is the activation path. The personal key at
`~/.config/sops/age/keys.txt` is for the `sops` command, not for activation.
If you prefer an age key file for activation, set `sops.age.keyFile` to an
absolute path outside the Nix store. That file must be readable by root.

On macOS, `neededForUsers` has no effect: nix-darwin cannot manage user
passwords. Run the auto-login command from an activation script that runs after
sops, or from a LaunchDaemon ordered after `sops-install-secrets`.

## Add a secret

1. Add the key to `secrets/secrets.yaml` with `sops`.
2. Declare it in the host module with `sops.secrets."name" = { };`.
3. Read it from the path in `sops.secrets."name".path`.
4. Rebuild the host that reads it.

For a secret that must exist before a user logs in, set `neededForUsers = true`.

## Add or replace a recipient

1. Add the new `age1...` key to `.sops.yaml`.
2. Run `sops updatekeys secrets/secrets.yaml`.
3. Commit the re-encrypted file.
4. Rebuild both hosts.

Remove a recipient in the same way. `updatekeys` re-encrypts the data key for
the current recipient set.

## Rotate

```sh
sops rotate -i secrets/secrets.yaml
sops updatekeys secrets/secrets.yaml
```

Then rebuild both hosts. A rotation changes the data key; a recipient change
changes who can unwrap it. Do both when a host key is compromised.

## Recover

With the recovery key:

```sh
SOPS_AGE_KEY_FILE=~/recovery-keys.txt sops -d secrets/secrets.yaml
```

Generate a new personal key, add it to `.sops.yaml`, run `sops updatekeys`, and
rebuild. If a host key is lost, regenerate the host key, add the new recipient,
run `sops updatekeys`, and rebuild that host.

## Security notes

- FileVault is off on the Mac so auto-login works. Anyone with physical access
  can read the age key and the decrypted secrets. Treat the Mac as an appliance
  on a trusted tailnet, not as a stolen-laptop-safe device.
- The personal key is a bearer credential. Passwords.app is the backup, not a
  runtime dependency.
- The `apw` Linux port is a separate project. anix does not call it yet.
