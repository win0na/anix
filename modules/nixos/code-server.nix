{ config, lib, pkgs, ... }:

let
  passwordSecret = config.sops.secrets."code-server-password".path;

  start = pkgs.writeShellScript "code-server-start" ''
    set -eu
    export PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/code-server-password")"
    exec ${lib.getExe pkgs.code-server} \
      --bind-addr 0.0.0.0:8080 \
      --auth password \
      --user-data-dir /home/winona/.local/share/code-server \
      --disable-telemetry \
      --disable-update-check
  '';
in
{
  systemd.services.code-server = {
    description = "code-server";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];

    environment = {
      HOME = "/home/winona";
      XDG_CONFIG_HOME = "/home/winona/.config";
      XDG_DATA_HOME = "/home/winona/.local/share";
      XDG_CACHE_HOME = "/home/winona/.cache";
      XDG_STATE_HOME = "/home/winona/.local/state";
    };

    serviceConfig = {
      User = "winona";
      Group = "users";
      WorkingDirectory = "/home/winona";
      LoadCredential = "code-server-password:${passwordSecret}";
      ExecStart = start;
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStopSec = "15s";
    };
  };

  networking.firewall.extraInputRules = ''
    ip saddr 100.64.0.0/10 tcp dport 8080 accept
  '';
}
