{ pkgs, system }:
let
  ciPrivateKey = pkgs.writeText "id_ed25519" ''
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACCWTaJ1D9Xjxy6759FvQ9oXTes1lmWBciXPkEeqTikBMAAAAJDQBmNV0AZj
    VQAAAAtzc2gtZWQyNTUxOQAAACCWTaJ1D9Xjxy6759FvQ9oXTes1lmWBciXPkEeqTikBMA
    AAAEDM1IYYFUwk/IVxauha9kuR6bbRtT3gZ6ZA0GLb9txb/pZNonUP1ePHLrvn0W9D2hdN
    6zWWZYFyJc+QR6pOKQEwAAAACGJmb0BtaW5pAQIDBAU=
    -----END OPENSSH PRIVATE KEY-----
  '';

  ciPublicKey = pkgs.writeText "id_ed25519.pub" ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZNonUP1ePHLrvn0W9D2hdN6zWWZYFyJc+QR6pOKQEw bob@client
  '';
in
pkgs.nixosTest
{
  name = "queued-build-hook-multiple-hosts";
  nodes = {
    cache = { ... }: {
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keyFiles = [ ciPublicKey ];
    };
    ci = { ... }: {
      imports = [ ../module.nix ];
      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';

      queued-build-hook = {
        enable = true;
        credentials = {
          ssh-key = builtins.toString ciPrivateKey;
        };
        postBuildScriptContent =
          let
            uploadPathsScript = pkgs.writeShellApplication {
              name = "upload-paths";
              runtimeInputs = [ pkgs.nix pkgs.openssh ];
              text = ''
                set -euo pipefail
                set -x
                # This is a dummy post-build-hook that copy over derivation to another host
                nix-store --generate-binary-cache-key cache1.example.org /tmp/sk1 /tmp/pk1
                nix --extra-experimental-features nix-command store sign --key-file /tmp/sk1 "$OUT_PATHS"
                echo "Uploading paths" "$OUT_PATHS"
                ls -l "$CREDENTIALS_DIRECTORY"
                export NIX_SSHOPTS="-o IdentityFile=''${CREDENTIALS_DIRECTORY}/ssh-key"
                exec nix copy --experimental-features nix-command --to "ssh://cache" "$OUT_PATHS"
              '';
            };
          in
          "${uploadPathsScript}/bin/upload-paths";
      };
      programs.ssh.extraConfig = ''
        UserKnownHostsFile /dev/null
        Host cache 
          User root
          Hostname cache
          IdentityFile ${ciPrivateKey}
          StrictHostKeyChecking accept-new
      '';

      system.extraDependencies = with pkgs; [ hello.inputDerivation ];
    };

  };
  testScript = ''
    start_all()

    helloPkg = ci.succeed("nix-instantiate ${pkgs.path} --json --eval -A hello.out.outPath| ${pkgs.jq}/bin/jq -r .").strip()
    with subtest("Test copy to another host"):
      cache.fail(f"ls -l '{helloPkg}' /nix/store")
      ci.succeed("nix-build --option substitute false --no-out-link -A hello ${pkgs.path}")
      cache.wait_for_file(f"{helloPkg}")

    with subtest("Already built package is not copied to the other host"):
      cache.succeed(f"nix-store --delete {helloPkg}")
      cache.fail(f"ls -l '{helloPkg}'")
      ci.succeed("nix-build --debug --option substitute false -A hello ${pkgs.path}")
      cache.sleep(2)
      cache.fail(f"ls -l '{helloPkg}'")
  '';
}

