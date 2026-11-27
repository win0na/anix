# Helpers for the install E2E. Loaded by each test file with `load lib`.

ANIX_E2E_TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export ANIX_E2E_TESTS
export ANIX_E2E_STUBS=$ANIX_E2E_TESTS/stubs
export PATH="$ANIX_E2E_STUBS:${ANIX_E2E_BIN:-}:$PATH"

e2e_setup() {
  fx=$BATS_TEST_TMPDIR/fx
  rm -rf "$fx"
  mkdir -p "$fx"
  mkdir -p "$fx/repo"
  tar -C "${ANIX_E2E_SOURCE:?}" --exclude=.git --exclude=result --exclude='pkgs/*/target' --exclude=./secrets/secrets.yaml -cf - . |
    tar -xf - -C "$fx/repo"
  cd "$fx/repo" || return 1
  git init -q -b personal
  git config user.name e2e
  git config user.email e2e@example.invalid

  cp "$ANIX_E2E_TESTS/fixtures/platform.sh" scripts/lib/platform.sh

  mkdir -p "$fx/home/.config/sops/age" "$fx/home/.ssh"
  chmod 700 "$fx/home/.config/sops/age" "$fx/home/.ssh"
  age-keygen -o "$fx/home/.config/sops/age/keys.txt" 2>/dev/null
  chmod 600 "$fx/home/.config/sops/age/keys.txt"
  ssh-keygen -q -t ed25519 -N '' -C anix-builder -f "$fx/home/.ssh/mac-builder"
  chmod 600 "$fx/home/.ssh/mac-builder"
  ssh-keygen -q -t ed25519 -N '' -C anix-device -f "$fx/home/.ssh/device"
  chmod 600 "$fx/home/.ssh/device"
  cp "$fx/home/.ssh/device.pub" "$fx/home/.ssh/authorized_keys"
  chmod 600 "$fx/home/.ssh/authorized_keys"
  age-keygen -o "$fx/recovery.txt" 2>/dev/null

  local pub recovery builder
  pub=$(age-keygen -y "$fx/home/.config/sops/age/keys.txt")
  recovery=$(age-keygen -y "$fx/recovery.txt")
  builder=$(cat "$fx/home/.ssh/mac-builder.pub")

  cat >users.nix <<NIX
{
  anix = "$E2E_USER";
  amac = "$E2E_USER";
  projectsDir = "src";
}
NIX

  cat >.sops.yaml <<SOPS
keys:
  personal: &personal $pub
  recovery: &recovery $recovery

creation_rules:
  - path_regex: ^secrets/[^/]+\.yaml$
    age:
      - *personal
      - *recovery
SOPS

  mkdir -p secrets
  local plain
  plain=secrets/.plain.yaml
  {
    printf 'mac-builder-key: |\n'
    sed 's/^/  /' "$fx/home/.ssh/mac-builder"
    printf 'cachix-token: ""\n'
    printf 'mac-login-password: ""\n'
  } >"$plain"
  sops --encrypt --age "$pub,$recovery" "$plain" >secrets/secrets.yaml
  rm -f "$plain"
  chmod 600 secrets/secrets.yaml

  sed -i "s|builderKey = \"[^\"]*\"|builderKey = \"$builder\"|" home/default/amac.nix

  mkdir -p "$fx/home/src/proj-one" "$fx/home/notes" "$fx/home/.vscode/cli"
  printf '{}\n' >"$fx/home/.vscode/cli/token.json"

  git add -A
  git commit -qm "test: fixture"

  local dir=$fx/wsl/distros/Ubuntu
  mkdir -p "$dir/home/$E2E_USER" "$dir/users" "$dir/root" "$fx/win/Users/e2e/AppData/Local/Temp" \
    "$fx/mac" "$fx/mac-system/etc/ssh"
  touch "$dir/users/$E2E_USER"
  ssh-keygen -q -t ed25519 -N '' -f "$fx/mac-system/etc/ssh/ssh_host_ed25519_key"

  export HOME=$fx/home
  export ANIX_E2E_SYSTEM=$fx/system
  export ANIX_E2E_WSL_ROOT=$fx/wsl
  export ANIX_E2E_WIN_ROOT=$fx/win
  export ANIX_E2E_WIN_HOME='C:\Users\e2e'
  export ANIX_E2E_WIN_TEMP='C:\Users\e2e\AppData\Local\Temp'
  export ANIX_E2E_MAC_HOME=$fx/mac
  export ANIX_E2E_MAC_SYSTEM=$fx/mac-system
  export WSL_DISTRO_NAME=Ubuntu
}

e2e_repo() { printf '%s\n' "$fx/repo"; }

e2e_distro_home() {
  printf '%s\n' "$ANIX_E2E_WSL_ROOT/distros/$1/home/$E2E_USER"
}

assert_file() { [[ -e $1 ]] || { echo "missing file: $1" >&2; return 1; }; }

assert_nonempty() { [[ -s $1 ]] || { echo "empty file: $1" >&2; return 1; }; }

assert_mode() {
  local mode
  mode=$(stat -c '%a' "$1")
  [[ $mode == "$2" ]] || { echo "mode $mode != $2 for $1" >&2; return 1; }
}

assert_contains() {
  [[ $1 == *"$2"* ]] || { echo "missing text: $2" >&2; return 1; }
}

E2E_USER=${E2E_USER:-$(id -un)}
export E2E_USER
: "${ANIX_E2E_SOURCE:=$(cd "$ANIX_E2E_TESTS/../.." && pwd)}"
export ANIX_E2E_SOURCE
