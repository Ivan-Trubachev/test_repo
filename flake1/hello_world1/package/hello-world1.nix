{
  lib,
  pkgs,
  stdenv,
  pkg-config,
  ...
}:
stdenv.mkDerivation rec {
  pname = "OSF";
  version = "v0.1";

  src = ./utils;
  
  nativeBuildInputs = [pkg-config];
  buildInputs = [ pkgs.bash ];

  buildPhase = ''
    cd hello_world1
    echo $PWD
    make
    cd ../
  '';

  installPhase = ''
    # Copy binaries
    mkdir -p $out/bin
    cp hello_world1/hello_world1 $out/bin
  '';
}
