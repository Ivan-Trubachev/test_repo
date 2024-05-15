# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.test-app;
  app-pkg = pkgs.callPackage ./pkg/test_app.nix {};
in
  with lib; {
    options.test-app = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If enabled, Test app module will be installed
        '';
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [
        app-pkg
      ];

    systemd.services.mesh = {
      enable = false;
      description = "Test_app_service";
      wantedBy = [ "default.target" ];
      serviceConfig.After = [ "dbus.service" ];
      serviceConfig.ExecStart = "${pkgs.bash}/bin/bash -c 'logger -t "TEST" "Here we are"'";
      serviceConfig.ExecSearchPath ="/run/current-system/sw/bin";
      serviceConfig.Environment ="PATH=$PATH:/run/current-system/sw/bin";
      serviceConfig.Restart = "always";
    };
  };
}