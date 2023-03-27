{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
}:
let
  queued-build-hook = import ./. { };
  dummy-hook = pkgs.writeShellScriptBin "dummy-hook" ''
    # This is a dummy post-build-hook that copy over derivation to another directory
    mkdir -p /var/nix-cache
    echo "Uploading paths" $OUT_PATHS
    exec ${pkgs.nix}/bin/nix copy --experimental-features nix-command --to "file:///var/nix-cache" $OUT_PATHS
  '';
  socketPath = "/var/lib/nix/async-nix-post-build-hook.socket";
  enqueue-package = pkgs.writeShellScriptBin "enqueue-package" ''
    ${queued-build-hook}/bin/queued-build-hook queue --socket ${socketPath}
  '';
in
pkgs.nixosTest
{
  name = "queued-build-hook";
  nodes = {
    ci = { ... }: {
      nix.settings.post-build-hook = "${enqueue-package}/bin/enqueue-package";

      system.extraDependencies = with pkgs; [ hello.inputDerivation ];

      systemd.tmpfiles.rules = [
        "d /var/nix-cache 0770 root nixbld - -"
      ];

      systemd.sockets = {
        async-nix-post-build-hook = {
          description = "Async nix post build hooks socket";
          wantedBy = [ "sockets.target" ];
          socketConfig = {
            ListenStream = socketPath;
            SocketMode = "0660";
            SocketGroup = "nixbld";
            Service = "async-nix-post-build-hook.service";
          };
        };
      };
      systemd.services = {
        async-nix-post-build-hook = {
          description = "Run nix post build hooks asynchronously";
          wantedBy = [ "multi-user.target" ];
          requires = [
            "async-nix-post-build-hook.socket"
          ];
          serviceConfig = {
            Type = "notify";
            ExecStart = "${queued-build-hook}/bin/queued-build-hook daemon --hook ${dummy-hook}/bin/dummy-hook";
            RestrictAddressFamilies = "AF_UNIX";
            FileDescriptorStoreMax = 1;
          };
        };
      };
    };

  };
  testScript = ''
    start_all()
    ci.succeed("nix-build --no-substitute -A hello '${<nixpkgs>}'")
    # Cache should contain a .narinfo referring to "hello"
    ci.wait_until_succeeds("grep -l 'StorePath: /nix/store/[[:alnum:]]*-hello-.*' /var/nix-cache/*.narinfo")
  '';
}

