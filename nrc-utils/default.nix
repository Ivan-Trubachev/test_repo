# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}: let
  nrc-utils = pkgs.stdenv.mkDerivation rec {
    pname = "nrc-utils";
    version = "1.5";

    src = pkgs.fetchFromGitHub {
      owner = "newracom";
      repo = "nrc7292_sw_pkg";
      rev = "v${version}";
      hash = "sha256-FOye8B7QaAQAWNbbmZdj9jrkzmp8u/ufHtbReup63EE=";
    };
    sourceRoot = "${src.name}/package/src/cli_app";
    
    # Rename target to nrc_cli for convenience
    prePatch = ''
      substituteInPlace ./Makefile --replace cli_app nrc_cli
    '';

    # Makefile does not have an install rule -> add custom one
    installPhase = ''
      mkdir -p $out/bin
      install -m 755 nrc_cli $out/bin
    '';

    meta = with lib; {
      description = "NRC7292 Software Package for Host mode (CLI App)";
      homepage = "https://github.com/newracom/nrc7292_sw_pkg";
      license = licenses.gpl2Only;
      maintainers = with lib.maintainers;[ IvanTrubachev ];
      platforms = with lib.platforms; linux;
    };
  };
in
  with lib; {
    environment.systemPackages = with pkgs; [
      nrc-utils
    ];
}
