{ inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    ../../modules/nixos/code-server.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."mac-builder-key" = {
      path = "/etc/nix/mac-builder";
      mode = "0400";
    };

    secrets."cachix-token" = { };

    secrets."code-server-password" = { };

    secrets."opencode-9router-api-key" = {
      key = "opencode/9router-api-key";
      owner = "winona";
      mode = "0400";
    };
  };
}
