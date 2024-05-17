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
  fw = ./firmware;
  service = ./service;
  
  nativeBuildInputs = [pkg-config];
  buildInputs = [ pkgs.bash ];

  buildPhase = ''
    cd ${src}/tunslip_clipcmd
    make 
    cd ${src}
  '';

  installPhase = ''

    mkdir -p $out/bin
    cp tunslip6 $out/bin
    cp slipcmd $out/bin

    # Export scripts
    cp -r ${service}/* $out/bin
    chmod +x $out/bin/osf_control.sh
    patchShebangs $out/bin

    # Copy firmware
    mkdir -p $out/lib/firmware/osf/nrf52
    cp -r ${fw}/nrf52/* $out/lib/firmware/osf/nrf52

  '';
}
