# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.nxp.mwifiex-drv;
  mwifiex-drv = config.boot.kernelPackages.callPackage ./packages/mwifiex.nix {};
in
  with lib; {
    options.nxp.mwifiex-drv = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If enabled, NXP driver for AzureWave CM358 driver modules will be installed
        '';
      };
    };
    
    config = mkIf cfg.enable {
        # Export kernel modules and perform modprobe on boot with arguments
        boot.extraModulePackages = [ mwifiex-drv ];
        boot.kernelModules = [ "mlan" "moal"];
        boot.extraModprobeConfig = ''
          options moal sta_name=sta uap_name=sap max_vir_bss=1 cfg80211_wext=0xf cal_data_cfg=none fw_name=NXP8987/sdiouart8987_combo_v0.bin
          '';
    };
  }