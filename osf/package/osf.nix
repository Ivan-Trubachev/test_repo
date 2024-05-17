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
  firmware = ./firmware;
  service = ./service;
  tests = ./tests;
  
  nativeBuildInputs = [pkg-config];
  buildInputs = [ pkgs.bash ];

  buildPhase = ''
    cd tunslip_slipcmd
    echo $PWD
    make
    cd ../
  '';

  installPhase = ''

    mkdir -p $out/bin
    cp tunslip_slipcmd/tunslip6 $out/bin
    cp tunslip_slipcmd/slipcmd $out/bin

    # Export scripts
    cp -r ${service}/* $out/bin
    chmod +x $out/bin/osf_control.sh
    patchShebangs $out/bin

    # Copy firmware
    mkdir -p $out/lib/firmware/osf/nrf52
    cp -r ${firmware}/nrf52/* $out/lib/firmware/osf/nrf52

    # Copy tests
    mkdir -p $out/bin/osf/test
    cp -r ${tests}/* $out/bin/osf/test
    chmod +x $out/bin/osf/test/test_osf_interface.sh
    chmod +x $out/bin/osf/test/test_osf_config_1M_1.sh
    chmod +x $out/bin/osf/test/test_osf_config_1M_2.sh
    chmod +x $out/bin/osf/test/test_osf_config_2M.sh
    chmod +x $out/bin/osf/test/test_osf_config_125K.sh
    chmod +x $out/bin/osf/test/test_osf_config_500K.sh
    chmod +x $out/bin/osf/test/test_osf_join_mcast_group.sh
    chmod +x $out/bin/osf/test/test_osf_send_mcast_udp.sh
    chmod +x $out/bin/osf/test/test_start_iperf3_server.sh
    chmod +x $out/bin/osf/test/test_osf_performance_1M.sh
    chmod +x $out/bin/osf/test/test_osf_performance_125K.sh
    chmod +x $out/bin/osf/test/test_osf_performance_overflow.sh
    chmod +x $out/bin/osf/test/test_osf_read_statistics.sh
    chmod +x $out/bin/osf/test/test_osf_reset_config.sh
    chmod +x $out/bin/osf/test/test_osf_stop_start_driver.sh
    chmod +x $out/bin/osf/test/test_slip_commands.sh
    chmod +x $out/bin/osf/test/test_udp_commands.sh
    patchShebangs $out/bin/osf/test
  '';
}
