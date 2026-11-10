{ inputs, ... }:

{
  imports = [ inputs.sops-nix-2605.darwinModules.sops ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."mac-login-password" = { };
  };
}
