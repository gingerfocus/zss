{ lib, stdenv, zig }:
stdenv.mkDerivation {
  pname = "zss";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ zig ];
  buildInputs = [ ];

  buildPhase =
    "${zig}/bin/zig build --prefix $out --cache-dir /build/zig-cache --global-cache-dir /build/global-cache -Doptimize=ReleaseSafe";
}
