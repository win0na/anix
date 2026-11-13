{
  lib,
  pkgs,
  hostSystem,
  # The Intel Mac installs MacPorts as root; the parameter stays in the
  # signature because it comes from the shared amac specialArgs and the pkg
  # postinstall must never rewrite this user's dotfiles.
  userName,
  ...
}:

let
  isIntel = hostSystem == "x86_64-darwin";

  prefix = "/opt/local";
  pkgVersion = "2.12.7";
  # The 26-Tahoe pkg is universal and the only build that runs on macOS 26.
  pkg = pkgs.fetchurl {
    url = "https://github.com/macports/macports-base/releases/download/v${pkgVersion}/MacPorts-${pkgVersion}-26-Tahoe.pkg";
    hash = "sha256-WI8UzNPGGZVZoHCoDmzd1ocXIaCMxDR3W/VDeP1meRA=";
  };
in
{
  # MacPorts first: its own docs and ports expect /opt/local/bin ahead of the
  # system prefix, and the Intel host installs there.
  environment.systemPath = lib.mkIf isIntel (lib.mkBefore [
    "${prefix}/bin"
    "${prefix}/sbin"
  ]);

  # Activation runs as root with a minimal PATH. postActivation is one of the
  # few keys nix-darwin dispatches, and mkBefore keeps this before the sops
  # autologin block (1500/1600) and before Home Manager's own text.
  system.activationScripts.postActivation.text = lib.mkIf isIntel (lib.mkBefore ''
    # The pkg installer writes /opt/local as root and its postinstall runs
    # `port -v selfupdate` in root's shell; nothing here touches
    # /Users/${userName}.
    macports_prefix=${prefix}

    macports_have=$(
      "$macports_prefix/bin/port" version 2>/dev/null | /usr/bin/awk '{ print $2 }' || true
    )
    # Install only a missing or wrong release, and only once: the sentinel says
    # a pkg install already succeeded, so a removed prefix is not re-created
    # behind the operator's back on every switch.
    if [ ! -e "$macports_prefix/.anix-pkg-588f14cc" ] && [ "$macports_have" != "${pkgVersion}" ]; then
      if /usr/sbin/installer -pkg ${pkg} -target /; then
        /usr/bin/touch "$macports_prefix/.anix-pkg-588f14cc"
      else
        echo "macports: pkg install failed; rerun: sudo installer -pkg ${pkg} -target /" >&2
      fi
    fi

    if [ -x "$macports_prefix/bin/port" ]; then
      # Refresh the port index only. selfupdate rebuilds MacPorts itself and
      # can take minutes, so a stale index wins over a failed switch.
      if ! ${lib.getExe' pkgs.coreutils "timeout"} 120 "$macports_prefix/bin/port" sync; then
        echo "macports: port sync failed; run: sudo port sync" >&2
      fi
    fi

    # The shim serves brew's layout out of the MacPorts prefix, so mirror each
    # installed port as <prefix>/Cellar/<name>/<version> and <prefix>/opt/<name>.
    # Both are symlinks to the prefix, where the real files live.
    if macports_installed=$("$macports_prefix/bin/port" -q installed 2>/dev/null); then
      /bin/mkdir -p "$macports_prefix/Cellar" "$macports_prefix/opt"
      printf '%s\n' "$macports_installed" | /usr/bin/awk '
        $2 ~ /^@/ {
          name = $1
          version = $2
          sub(/^@/, "", version)
          sub(/\+.*$/, "", version)
          sub(/_[0-9]+$/, "", version)
          if (name != "" && version != "") print name, version
        }
      ' | while read -r macports_name macports_version; do
        macports_cellar="$macports_prefix/Cellar/$macports_name"
        /bin/mkdir -p "$macports_cellar"
        macports_link="$macports_cellar/$macports_version"
        if [ -L "$macports_link" ] || [ ! -e "$macports_link" ]; then
          /bin/ln -sfn "$macports_prefix" "$macports_link"
        fi
        macports_opt="$macports_prefix/opt/$macports_name"
        if [ -L "$macports_opt" ] || [ ! -e "$macports_opt" ]; then
          /bin/ln -sfn "$macports_prefix" "$macports_opt"
        fi
      done
      # A link whose target vanished is worse than no link.
      for macports_link in "$macports_prefix"/opt/*; do
        [ -L "$macports_link" ] || continue
        [ -e "$macports_link" ] || /bin/rm -f "$macports_link"
      done
      for macports_cellar in "$macports_prefix"/Cellar/*; do
        [ -d "$macports_cellar" ] || continue
        /bin/rmdir "$macports_cellar" 2>/dev/null || true
      done
    else
      echo "macports: port -q installed failed; leaving the brew-shaped tree alone" >&2
    fi
  '');
}
