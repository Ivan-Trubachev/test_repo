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
  nrc-drv = pkgs.stdenv.mkDerivation rec {
    pname = "nrc7292";
    version = "v1.5";
    src = pkgs.fetchFromGitHub {
      owner = "newracom";
      repo = "nrc7292_sw_pkg";
      rev = "cdbe1f92de563a48b5518de8d1d1dfab2b731ca0";
      hash = "sha256-8ZwbvLP1FBQNiiZKZDfaOHghFu/iaRo1jbI8NOkXImk=";
    };
    sourceRoot = "${src.name}/package/src/nrc";
    hardeningDisable = [ "pic" ];
    nativeBuildInputs = [ pkgs.bc ] ++ kpkgs.kernel.moduleBuildDependencies;

    firmware = ./firmware;

    patches = [
      # Fix install rules and add 6.1 kernel support
      ./patches/0001-Add-support-for-6.1-kernel.patch
      ./patches/0002-Fix-NRC-init-error-messages.patch
    ];

    preInstall = ''
      mkdir -p "$out/lib/modules/${kpkgs.kernel.modDirVersion}/kernel/net/wireless/"
      mkdir -p $out/lib/firmware

      cp -r $firmware/* $out/lib/firmware
    '';

    prePatch = ''
      substituteInPlace ./Makefile \
        --replace /lib/modules/ "${kpkgs.kernel.dev}/lib/modules/" \
        --replace /sbin/depmod \# \
        --replace '$(MODDESTDIR)' "$out/lib/modules/${kpkgs.kernel.modDirVersion}/kernel/net/wireless/"
    '';

    makeFlags = kpkgs.kernel.makeFlags ++ [
      "KERNELRELEASE=${kpkgs.kernel.modDirVersion}"
      "KERNEL_DIR=${kpkgs.kernel.dev}/lib/modules/${kpkgs.kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)/lib/modules/${kpkgs.kernel.modDirVersion}/kernel/net/wireless/"
    ];

    extraConfig = ''
      NRC7292 m
    '';

    enableParallelBuilding = true;

    meta = with lib; {
      description = "NRC7292 Software Package for Host mode (Linux OS)";
      homepage = "https://github.com/newracom/nrc7292_sw_pkg";
      maintainers = with lib.maintainers;[ IvanTrubachev ];
      license = licenses.gpl2Only;
      platforms = platforms.linux;
    };
  };
in
  with lib; {
    config = {
         boot.extraModulePackages = [ nrc-drv ];
    };
}
