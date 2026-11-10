{ inputs, ... }:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."mac-builder-key" = {
      path = "/etc/nix/mac-builder";
      mode = "0400";
    };

    secrets."cachix-token" = { };
  };
}
