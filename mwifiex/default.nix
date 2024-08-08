# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  kernel,
  kmod,
  ...
}: let
  kpkgs = config.boot.kernelPackages;
  mwifiex-drv = pkgs.stdenv.mkDerivation rec {
    pname = "mwifiex";
    version = "lf-6.6.3_1.0.0";

    firmware = ./firmware;

    src = pkgs.fetchFromGitHub {
      owner = "nxp-imx";
      repo = "mwifiex";
      rev = "a84df583155bad2a396a937056805550bdf655ab";
      hash = "sha256-4RnvJN2vo0DF2kOuWfamn64tQaopcaEiSSIQMFZn6fg=";
    };
    sourceRoot = "${src.name}/mxm_wifiex/wlan_src";

    # Add bc so the makefile can correctly detect GCC version
    nativeBuildInputs = [ pkgs.bc ] ++ kpkgs.kernel.moduleBuildDependencies;
    hardeningDisable = [ "pic" "format" ];

    patches = [ ./patches/0001-mwifiex-makefile.patch ];

    makeFlags = kpkgs.kernel.makeFlags ++ [
      "NIX_KERNEL_DEV=${kpkgs.kernel.dev}"
      "KERNELDIR=${kpkgs.kernel.dev}/lib/modules/${kpkgs.kernel.modDirVersion}/build"
      "INSTALLDIR=${placeholder "out"}/lib/modules/${kpkgs.kernel.modDirVersion}/kernel/net/wireless/"
    ];

    enableParallelBuilding = true;

    preInstall = ''
      mkdir -p $out/lib/firmware

      cp -r $firmware/* $out/lib/firmware
    '';

    meta = with lib; {
      description = "NXP Wi-Fi linux driver";
      homepage = "https://github.com/nxp-imx/mwifiex";
      license = licenses.gpl2Only;
      maintainers = with lib.maintainers;[ IvanTrubachev ];
      platforms = platforms.linux;
    };
  };
in
  with lib; {
    config = {
        services.udev.packages = lib.singleton (pkgs.writeTextFile
        { 
          name = "aw-cm358-rules";
          text = ''
            # AW-CM358SM wifi module
            SUBSYSTEM=="net", DEVPATH=="*/mmc0:0001/mmc0:0001:1/net/sta0", ACTION=="add", NAME:="wlan1"
          '';
          destination = "/etc/udev/rules.d/70-wifi-awcm358.rules";
        });

        # Export kernel modules and perform modprobe on boot with arguments
        boot.extraModulePackages = [ mwifiex-drv ];
        boot.kernelModules = [ "mlan" "moal"];
        boot.extraModprobeConfig = ''
          options moal sta_name=sta uap_name=sap max_vir_bss=1 cfg80211_wext=0xf cal_data_cfg=none fw_name=NXP8987/sdiouart8987_combo_v0.bin
          '';
    };
  }