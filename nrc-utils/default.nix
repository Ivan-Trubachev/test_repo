# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.nrc-utils;
  nrc-utils = pkgs.callPackage ./package/nrc-utils.nix {};
in
  with lib; {
    options.nrc-utils = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If enabled, NRC utils will be installed
        '';
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        nrc-utils
      ];
    };
}