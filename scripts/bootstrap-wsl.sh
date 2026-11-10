#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-wsl.sh [options]

Bootstrap a fresh NixOS-WSL host as winona: check the environment, clone the
repository, verify the sops age key, and switch the anix configuration.

Options:
  -h, --help    Show this help and exit.
  --no-switch   Skip the final nixos-rebuild switch.
  --repo URL    Clone from URL instead of ANIX_REPO_URL or
                https://github.com/win0na/anix.git.

Environment:
  ANIX_REPO_URL  Default clone URL. The --repo flag overrides it.
EOF
}

no_switch=0
repo_url="${ANIX_REPO_URL:-https://github.com/win0na/anix.git}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --no-switch)
      no_switch=1
      shift
      ;;
    --repo)
      if [[ $# -lt 2 ]]; then
        echo "error: --repo requires a URL" >&2
        exit 2
      fi
      repo_url="$2"
      shift 2
      ;;
    --repo=*)
      repo_url="${1#*=}"
      shift
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "error: this bootstrap runs on NixOS-WSL (Linux), found $(uname -s)" >&2
  exit 1
fi

if [[ ! -e /etc/NIXOS ]]; then
  echo "error: /etc/NIXOS not found; this host is not NixOS" >&2
  exit 1
fi

if ! command -v wsl.exe >/dev/null 2>&1; then
  echo "warning: wsl.exe not on PATH; WSL interop may be disabled" >&2
fi

checkout="$HOME/src/anix"
if [[ -d "$checkout/.git" ]]; then
  echo "==> using existing checkout at $checkout"
elif [[ -e "$checkout" ]]; then
  echo "error: $checkout exists but is not a git checkout; move it aside" >&2
  exit 1
else
  if ! command -v git >/dev/null 2>&1; then
    echo "error: git not found on PATH; clone the repository first" >&2
    exit 1
  fi
  mkdir -p "$HOME/src"
  echo "==> git clone $repo_url $checkout"
  git clone "$repo_url" "$checkout"
fi

key="$HOME/.config/sops/age/keys.txt"
if [[ ! -f "$key" ]]; then
  echo "error: sops age key not found: $key" >&2
  echo "Restore the key from your offline backup, or create a new one:" >&2
  echo "  mkdir -p \"$HOME/.config/sops/age\"" >&2
  echo "  age-keygen -o \"$key\"" >&2
  echo "Then add its public key to .sops.yaml and re-encrypt the secrets." >&2
  exit 1
fi

if [[ $no_switch -eq 1 ]]; then
  echo "==> skipping nixos-rebuild (--no-switch)"
  exit 0
fi

echo "==> sudo nixos-rebuild switch --flake $checkout#anix"
sudo nixos-rebuild switch --flake "$checkout#anix"
