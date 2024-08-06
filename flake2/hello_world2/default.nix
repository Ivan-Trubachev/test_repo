# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.hello-world2;
  helloworld2-pkg = pkgs.callPackage ./package/hello-world2.nix {};
in
  with lib; {
    options.hello-world2 = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If enabled, hello world module will be installed
        '';
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [
        helloworld2-pkg
      ];
  };
}