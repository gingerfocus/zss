{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }: let
    lib = nixpkgs.lib;
    systems = [ "aarch64-linux" "x86_64-linux" ];
    eachSystem = f: lib.foldAttrs lib.mergeAttrs { } (map (s: lib.mapAttrs (_: v: { ${s} = v; }) (f s)) systems);
    # forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in
    eachSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "zss";
          version = "0.1.0";

          nativeBuildInputs = with pkgs; [ ];
          buildInputs = with pkgs; [ ];

          src = self;

          buildPhase = "${pkgs.zig}/bin/zig build --prefix $out --cache-dir /build/zig-cache --global-cache-dir /build/global-cache -Doptimize=ReleaseSmall";

          # shellHook = ''export VIMRUNTIME=$PWD/runtime'';

          meta = {
            maintainers = ["Evan Stokdyk <evan.stokdyk@gmail.com>"];
            description = "Tree Sitter Pre-Processor for Shards";
          };
        };
      });
}

