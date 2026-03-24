{
  description = "A flake for getting the most recent release of zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = inputs @ { flake-parts, ...}: 
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [];
      systems = ["x86_64-linux" "x86_64-darwin"];
      perSystem = {pkgs, self', system,...}: {
        packages.zig = inputs.zig.packages.${system}.master;

        devShells.default = pkgs.mkShell {
          packages = [
            self'.packages.zig
          ];  
        };
      };
    };
}
