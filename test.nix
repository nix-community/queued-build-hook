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
          # This is a dummy post-build-hook that copy over derivation to another directory
          mkdir -p /var/nix-cache
          echo "Uploading paths" $OUT_PATHS
          exec ${pkgs.nix}/bin/nix copy --experimental-features nix-command --to "file:///var/nix-cache" $OUT_PATHS
        '';
      };

      system.extraDependencies = with pkgs; [ hello.inputDerivation ];
    };

  };
  testScript = ''
    start_all()
    ci.succeed("nix-build --no-substitute -A hello '${<nixpkgs>}'")
    # Cache should contain a .narinfo referring to "hello"
    ci.wait_until_succeeds("grep -l 'StorePath: /nix/store/[[:alnum:]]*-hello-.*' /var/nix-cache/*.narinfo")
  '';
}

