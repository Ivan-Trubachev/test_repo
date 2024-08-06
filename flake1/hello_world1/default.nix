# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.hello-world1;
  helloworld1-pkg = pkgs.callPackage ./package/hello-world1.nix {};
in
  with lib; {
    options.hello-world1 = {
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
        helloworld1-pkg
      ];
  };
}