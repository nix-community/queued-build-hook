{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.go
    pkgs.rustfmt
    # Systemd socket activation development tool
    pkgs.systemfd
  ];

  shellHook = ''
    unset GOPATH
  '';
}
