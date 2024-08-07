{
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,
  kernel,
}:
stdenv.mkDerivation rec {
  pname = "mwifiex";
  version = "lf-6.6.3_1.0.0";

  firmware = ./firmware;

  src = fetchFromGitHub {
    owner = "nxp-imx";
    repo = "mwifiex";
    rev = "a84df583155bad2a396a937056805550bdf655ab";
    hash = "sha256-4RnvJN2vo0DF2kOuWfamn64tQaopcaEiSSIQMFZn6fg=";
  };
  sourceRoot = "${src.name}/mxm_wifiex/wlan_src";

  # Add bc so the makefile can correctly detect GCC version
  nativeBuildInputs = kernel.moduleBuildDependencies ++ [pkgs.bc];
  hardeningDisable = [ "pic" "format" ];

  patches = [ ./patches/0001-mwifiex-makefile.patch ];

  makeFlags = kernel.makeFlags ++ [
    "NIX_KERNEL_DEV=${kernel.dev}"
    "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALLDIR=${placeholder "out"}/lib/modules/${kernel.modDirVersion}/kernel/net/wireless/"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    mkdir -p $out/lib/firmware

    cp -r $firmware/* $out/lib/firmware
  '';

  meta = with lib; {
    description = "NXP Wi-Fi linux driver";
    homepage = "https://github.com/nxp-imx/mwifiex";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
