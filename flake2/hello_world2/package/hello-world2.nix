{
  lib,
  pkgs,
  stdenv,
  pkg-config,
  ...
}:
stdenv.mkDerivation rec {
  pname = "Hello-world2";
  version = "v0.1";

  src = ./utils;
  
  nativeBuildInputs = [pkg-config];
  buildInputs = [ pkgs.bash ];

  buildPhase = ''
    cd hello_world2
    echo $PWD
    make
    cd ../
  '';

  installPhase = ''
    # Copy binaries
    mkdir -p $out/bin
    cp hello_world2/hello_world2 $out/bin
  '';
}
