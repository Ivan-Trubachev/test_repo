# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.nrc-drv;
  nrc-drv = pkgs.callPackage ./package/nrc-drv.nix {};
in
  with lib; {
    options.nrc-drv = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If enabled, NRC7292 driver will be installed
        '';
      };
    };

    config = mkIf cfg.enable {
         boot.extraModulePackages = [ nrc-drv ];
    };
}