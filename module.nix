{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.queued-build-hook;
  queued-build-hook = pkgs.callPackage ./. { };
in
{
  options.queued-build-hook = {
    enable = mkEnableOption "queued-build-hook";

    package = mkOption {
      type = types.package;
      default = queued-build-hook;
      description = mdDoc ''
        The queued-build-hook package to use.
      '';
    };

    socketDirectory = mkOption {
      description = mdDoc ''
        Path to store the queued-build-hook daemon's unix socket.
      '';
      default = "/var/lib/nix";
      type = types.path;
    };

    socketUser = mkOption {
      type = types.str;
      example = "user";
      default = "root";
      description = mdDoc ''
        This users will have read/write access to the Unix socket.
      '';
    };

    socketGroup = mkOption {
      description = mdDoc ''
        The users in this group will have read/write access to the Unix socket.
      '';
      type = types.str;
      default = "nixbld";
    };

    retryInterval = mkOption {
      description = mdDoc ''
        The number of seconds between attempts to run the hook for a package after an initial failure.
      '';
      type = types.int;
      default = 1;
    };

    retries = mkOption {
      description = mdDoc ''
        The maximum number of attempts that will be made to run the hook for a package before giving up and dropping the task altogether.
      '';
      type = types.int;
      default = 5;
    };

    concurrency = mkOption {
      description = mdDoc ''
        Sets the maximum number of tasks that can be executed simultaneously.
        By default it is set to 0 which means there is no limit to the number of tasks that can be run concurrently.
      '';
      type = types.int;
      default = 0;
    };

    enqueueScriptContent = mkOption {
      description = mdDoc ''
        The script's content responsible for enqueuing newly-built packages and passing them to the daemon.
        Although the default configuration should suffice, there may be situations that require customized handling of specific packages.
        For example, it may be necessary to process certain packages synchronously using the 'queued-build-hook wait' command, or to ignore certain packages entirely.
      '';
      default = ''
        ${cfg.package}/bin/queued-build-hook queue --socket "${cfg.socketDirectory}/async-nix-post-build-hook.sock"
      '';
      type = types.str;
    };

    postBuildScriptContent = mkOption {
      description = mdDoc ''
        Specify the content of the script that will manage the newly built package.
        The script must be able to handle the OUT_PATHS environment variable, which contains a list of the paths to the newly built packages.
      '';
      example = literalExpression ''
        exec nix copy --experimental-features nix-command --to "file:///var/nix-cache" $OUT_PATHS
      '';
      type = types.str;
    };

    credentials = mkOption {
      description = mdDoc ''
        Credentials to load by startup. Keys that are UPPER_SNAKE will be loaded as env vars. Values are absolute paths to the credentials.
      '';
      type = types.attrsOf types.str;
      default = { };

      example = {
        AWS_SHARED_CREDENTIALS_FILE = "/run/keys/aws-credentials";
        binary-cache-key = "/run/keys/binary-cache-key";
      };
    };

  };
  config = mkIf cfg.enable {

    nix.settings.post-build-hook =
      let
        enqueueScript = pkgs.writeShellScriptBin "enqueue-package" cfg.enqueueScriptContent;
      in
      "${enqueueScript}/bin/enqueue-package";

    systemd.sockets = {
      async-nix-post-build-hook = {
        description = "Async nix post build hooks socket";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "${cfg.socketDirectory}/async-nix-post-build-hook.sock";
          SocketMode = "0660";
          SocketUser = cfg.socketUser;
          SocketGroup = cfg.socketGroup;
          Service = "async-nix-post-build-hook.service";
        };
      };
    };

    systemd.services =
      let
        hook = pkgs.writeShellScript "hook" cfg.postBuildScriptContent;
      in
      {
        async-nix-post-build-hook = {
          description = "Run nix post build hooks asynchronously";
          wantedBy = [ "multi-user.target" ];
          requires = [
            "async-nix-post-build-hook.socket"
          ];
          script = ''
            set -euo pipefail
            shopt -u nullglob
            # Load all credentials into env if they are in UPPER_SNAKE form.
            if [[ -n "''${CREDENTIALS_DIRECTORY:-}" ]]; then
              for file in "$CREDENTIALS_DIRECTORY"/*; do
                key=$(basename "$file")
                if [[ $key =~ ^[A-Z0-9_]+$ ]]; then
                  echo "Environ $key"
                  export "$key=$(< "$file")"
                fi
              done
            fi
            exec ${cfg.package}/bin/queued-build-hook daemon --hook ${hook} --retry-interval ${toString cfg.retryInterval} --retry-interval ${toString cfg.retries} --concurrency ${toString cfg.concurrency} 
          '';
          serviceConfig = {
            DynamicUser = true;
            User = "queued-build-hook";
            Group = "queued-build-hook";
            LoadCredential = mapAttrsToList (key: value: "${key}:${value}") cfg.credentials;
            KillMode = "process";
            Restart = "on-failure";
            FileDescriptorStoreMax = 1;
          };
        };
      };
  };
}
