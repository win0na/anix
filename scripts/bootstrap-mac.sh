#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-mac.sh [options]

Bootstrap the Intel Mac: check macOS and Xcode, install Nix if asked, clone
the repository, warn when the sops age key is missing, and switch the amac
configuration.

Options:
  -h, --help     Show this help and exit.
  --no-switch    Skip the final darwin-rebuild switch.
  --install-nix  Install Nix with the upstream daemon installer when missing.
  --repo URL     Clone from URL instead of ANIX_REPO_URL or
                 https://github.com/win0na/anix.git.

Environment:
  ANIX_REPO_URL  Default clone URL. The --repo flag overrides it.
EOF
}

no_switch=0
install_nix=0
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
    --install-nix)
      install_nix=1
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

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this bootstrap runs on macOS, found $(uname -s)" >&2
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "error: this configuration targets the Intel Mac (x86_64), found $(uname -m)" >&2
  exit 1
fi

macos_version="$(sw_vers -productVersion)"
if [[ "$macos_version" != 26.* ]]; then
  echo "warning: expected macOS 26.x, found $macos_version" >&2
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "error: Xcode command line tools not installed. Run:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
  if [[ $install_nix -eq 1 ]]; then
    echo "==> curl -L https://nixos.org/nix/install | sh -s -- --daemon"
    curl -L https://nixos.org/nix/install | sh -s -- --daemon
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
      # shellcheck disable=SC1091
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
    if ! command -v nix >/dev/null 2>&1; then
      echo "error: nix still not on PATH after install; open a new shell" >&2
      exit 1
    fi
  else
    echo "error: nix not found on PATH. Install it with:" >&2
    echo "  curl -L https://nixos.org/nix/install | sh -s -- --daemon" >&2
    echo "Then open a new shell, or rerun with --install-nix." >&2
    exit 1
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  echo "error: git not found on PATH" >&2
  exit 1
fi

checkout="$HOME/.config/anix"
if [[ -d "$checkout/.git" ]]; then
  echo "==> using existing checkout at $checkout"
elif [[ -e "$checkout" ]]; then
  echo "error: $checkout exists but is not a git checkout; move it aside" >&2
  exit 1
else
  mkdir -p "$(dirname "$checkout")"
  echo "==> git clone $repo_url $checkout"
  git clone "$repo_url" "$checkout"
fi

key="$HOME/.config/sops/age/keys.txt"
if [[ ! -f "$key" ]]; then
  echo "warning: sops age key not found: $key" >&2
  echo "The switch can still run; activation uses the Mac host key." >&2
  echo "Restore the personal key from Passwords.app to edit secrets." >&2
fi

if [[ -n "${SSH_CONNECTION:-}" ]]; then
  echo "warning: running over SSH. The first switch should run from a GUI" >&2
  echo "warning: Terminal because macOS App Management can block writes to" >&2
  echo "warning: /Applications/Nix Apps over SSH." >&2
fi

if [[ $no_switch -eq 1 ]]; then
  echo "==> skipping darwin-rebuild (--no-switch)"
  exit 0
fi

echo "==> sudo darwin-rebuild switch --flake $checkout#amac"
sudo darwin-rebuild switch --flake "$checkout#amac"
