# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.nxp.plug-and-trust;
  plug-and-trust-pkg = pkgs.callPackage ./packages/plug-and-trust.nix {};
in
  with lib; {
    options.nxp.plug-and-trust = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If enabled, plug-and-trust binary (Plug and Trust middleware mini package) will be enabled.
        '';
      };
    };
    config = mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        plug-and-trust-pkg
      ];
    };
  }