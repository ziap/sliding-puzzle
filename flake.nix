{
  description = "Sliding puzzle solver's flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShell.${system} = pkgs.mkShell {
      buildInputs = [
        pkgs.zig

        # Debugger and benchmark tool
        pkgs.lldb
        pkgs.poop

        # Local web server
        pkgs.static-web-server

        # Wasm devtools
        pkgs.binaryen
        pkgs.wabt
      ];
    };
  };
}
