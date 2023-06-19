{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
}:
pkgs.nixosTest
{
  name = "queued-build-hook";
  nodes = {
    ci = { ... }: {
      imports = [ ./module.nix ];

      queued-build-hook = {
        enable = true;
        postBuildScriptContent = ''
          set -euo pipefail
          # This is a dummy post-build-hook that copy over derivation to another directory
          echo "Uploading paths" $OUT_PATHS
          echo "We can access secret environment variable SECRET_ENV_VAR: ''${SECRET_ENV_VAR}"
          echo "We can access secret file secret_file: ''$(cat ''${CREDENTIALS_DIRECTORY}/secret_file)"
          # Test Home/XDG directories
          mkdir -p $HOME/.tmp
          exec ${pkgs.nix}/bin/nix copy --experimental-features nix-command --to "file:///var/nix-cache" $OUT_PATHS
        '';
        credentials = {
          SECRET_ENV_VAR = "/run/keys/secret1";
          secret_file = "/run/keys/secret2";
        };
      };

      # Grant access to /var/nix-cache for the test
      systemd.tmpfiles.rules = [
        "d /var/nix-cache 0777 root - - -"
      ];
      systemd.services.async-nix-post-build-hook.serviceConfig.ReadWritePaths = [ "/var/nix-cache" ];

      # Create dummy secrets - use nix-sops or agenix instead
      system.activationScripts.createDummySecrets = ''
        echo "Tohgh3Th" > /run/keys/secret1
        echo "eQuei0xu" > /run/keys/secret2
      '';

      system.extraDependencies = with pkgs; [ hello.inputDerivation ];
    };

  };
  testScript = ''
    start_all()
    ci.succeed("nix-build --no-substitute -A hello '${pkgs.path}'")
    # Cache should contain a .narinfo referring to "hello"
    ci.wait_until_succeeds("grep -l 'StorePath: /nix/store/[[:alnum:]]*-hello-.*' /var/nix-cache/*.narinfo")
    # Check that the service can access secrets
    ci.succeed("journalctl -o cat -u async-nix-post-build-hook.service | grep 'We can access secret environment variable SECRET_ENV_VAR: Tohgh3Th'")
    ci.succeed("journalctl -o cat -u async-nix-post-build-hook.service | grep 'We can access secret file secret_file: eQuei0xu'")
    ci.succeed("test -d /var/lib/async-nix-post-build-hook/.tmp")
  '';
}

