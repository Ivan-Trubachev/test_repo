# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  plug-and-trust = pkgs.stdenv.mkDerivation rec {
    pname = "plug-and-trust";
    version = "04.03.01";

    # NXP Plug and Trust middleware 04.03.01 from 
    # https://ssrc.atlassian.net/wiki/spaces/SC/pages/806781314/HSM+SE050Cx+-+chip+support#Needed-files
    # with se05x_reset.c pre-applied
    src = ./src/SE05x-MW-v04.03.01.tar.gz;

    buildInputs = [ pkgs.openssl.dev ];
    nativeBuildInputs = [ pkgs.cmake pkgs.python3 ];
    
    # Fix error: '-Wformat-security' ignored without '-Wformat' [-Werror=format-security]
    # by enabling Wformat
    prePatch = ''
      substituteInPlace ./ext/mbedtls.cmake --replace Wno-format Wformat
    '';

    # Provide paths to OPENSSL so that CMake could find it
    # then execute python script that creates cmake atrifacts for us
    # and cd to directory with those artifacts
    preConfigure = ''
      cd scripts/

      export OPENSSL_INCLUDE_DIR=${pkgs.openssl.dev}/include
      export OPENSSL_LIB_DIR="${lib.getLib pkgs.openssl}/lib"

      python3 create_cmake_projects.py rpi
      
      cd $TMPDIR/simw-top_build/raspbian_native_se050_t1oi2c/
    '';

    # We are not doing interactive build, so set parameters according to 
    # https://ssrc.atlassian.net/wiki/spaces/SC/pages/806781314/HSM+SE050Cx+-+chip+support#Build-Steps
    # IMPORTANT: Original config suggests OpenSSL 1.1.1 but it is insecure and EOL, so was changed to 3.0
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Debug"
      "-DOPENSSL_ROOT_DIR="

      "-DNXPInternal=OFF"
      "-DPAHO_BUILD_DEB_PACKAGE=OFF"
      "-DPAHO_BUILD_DOCUMENTATION=OFF"
      "-DPAHO_BUILD_SAMPLES=OFF"
      "-DPAHO_BUILD_SHARED=ON"
      "-DPAHO_BUILD_STATIC=OFF"
      "-DPAHO_ENABLE_CPACK=ON"
      "-DPAHO_ENABLE_TESTING=OFF"
      "-DPAHO_WITH_SSL=ON"

      "-DPTMW_A71CH_AUTH=None"
      "-DPTMW_Applet=SE05X_C"
      "-DPTMW_FIPS=None"
      "-DPTMW_Host=Raspbian"
      "-DPTMW_HostCrypto=MBEDTLS"
      "-DPTMW_Log=Default"
      "-DPTMW_OpenSSL=3_0"
      "-DPTMW_RTOS=Default"
      "-DPTMW_SBL=None"
      "-DPTMW_SCP=None"
      "-DPTMW_SE05X_Auth=None"
      "-DPTMW_SE05X_Ver=03_XX"
      "-DPTMW_SMCOM=T1oI2C"
      "-DPTMW_mbedTLS_ALT=None"

      "-DSSSFTR_SE05X_AES=ON"
      "-DSSSFTR_SE05X_AuthECKey=ON"
      "-DSSSFTR_SE05X_AuthSession=ON"
      "-DSSSFTR_SE05X_CREATE_DELETE_CRYPTOOBJ=ON"
      "-DSSSFTR_SE05X_ECC=ON"
      "-DSSSFTR_SE05X_KEY_GET=ON"
      "-DSSSFTR_SE05X_KEY_SET=ON"
      "-DSSSFTR_SE05X_RSA=ON"
      "-DSSSFTR_SW_AES=ON"
      "-DSSSFTR_SW_ECC=ON"
      "-DSSSFTR_SW_KEY_GET=ON"
      "-DSSSFTR_SW_KEY_SET=ON"
      "-DSSSFTR_SW_RSA=ON"
      "-DSSSFTR_SW_TESTCOUNTERPART=ON"

      "-DWithAccessMgr_UnixSocket=OFF"
      "-DWithCodeCoverage=OFF"
      "-DWithExtCustomerTPMCode=OFF"
      "-DWithNXPNFCRdLib=OFF"
      "-DWithOPCUA_open62541=OFF"
      "-DWithSharedLIB=OFF"
    ];

    # Resulting file structure is slightly off after cmake fixup
    # (all cmake files are in parent directory)
    # so we manually invoke build and install commands
    # We also need to copy a library from a built demo app
    buildPhase = ''
      cmake --build ..
    '';

    installPhase = ''
      cmake --install ..
      install -m 644 ../demos/linux/sss_pkcs11/libsss_pkcs11.so $out/lib
    '';

    meta = {
      description = "NXP Plug and Trust middleware";
      homepage = "https://github.com/NXP/plug-and-trust";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers;[ IvanTrubachev ];
      platforms = with lib.platforms; linux;
    };
  };
in
  with lib; {
    config =  {
      environment.systemPackages = with pkgs; [
        plug-and-trust
      ];
    };
  }