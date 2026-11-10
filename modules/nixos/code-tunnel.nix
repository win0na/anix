{ config, lib, pkgs, ... }:

let
  extensionIds = lib.filter (line: line != "" && !lib.hasPrefix "#" line) (
    lib.splitString "\n" (builtins.readFile ../../home/winona/editors/extensions-remote.txt)
  );

  extensionArgs = lib.escapeShellArgs (
    lib.concatMap (id: [
      "--install-extension"
      id
    ]) extensionIds
  );
in
{
  programs.nix-ld.enable = true;

  systemd.services.code-tunnel = {
    description = "Microsoft code tunnel";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    startLimitBurst = 5;
    startLimitIntervalSec = 300;

    environment = {
      HOME = "/home/winona";
      VSCODE_CLI_USE_FILE_KEYCHAIN = "1";
      NIX_LD = config.environment.sessionVariables.NIX_LD;
      NIX_LD_LIBRARY_PATH = config.environment.sessionVariables.NIX_LD_LIBRARY_PATH;
    };

    unitConfig.ConditionPathExists = "/home/winona/.vscode/cli/token.json";

    serviceConfig = {
      User = "winona";
      Group = "users";
      WorkingDirectory = "/home/winona";
      ExecStart = "${lib.getExe pkgs.vscode-cli} tunnel --accept-server-license-terms --disable-telemetry --name anix ${extensionArgs}";
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStopSec = 15;
    };
  };
}
