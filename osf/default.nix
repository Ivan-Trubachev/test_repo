# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.osf;
  osf-pkg = pkgs.callPackage ./package/osf.nix {};
in
  with lib; {
    options.osf = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If enabled, OSF module will be installed
        '';
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [
        osf-pkg
      ];

    systemd.services.osf = {
      enable = true;
      description = "OSF service";
      wantedBy = [ "default.target" ];
      after = [ "systemd-logind.service" ];
      serviceConfig.ExecStart = "osf_control.sh setup /dev/nrf0 osf0 /dev/nrfdfu0";
      serviceConfig.ExecSearchPath ="/run/current-system/sw/bin";
      serviceConfig.Environment ="PATH=$PATH:/run/current-system/sw/bin";
      serviceConfig.Restart = "always";
    };
  };
}