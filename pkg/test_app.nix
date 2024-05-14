{
  lib,
  stdenv,
  pkg-config,
  gpsd,
}:
stdenv.mkDerivation rec {
  pname = "test_app";
  version = "v0.1";

  src = ./src;
  nativeBuildInputs = [pkg-config];

  buildInputs = [
    gpsd
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ./test_app $out/bin
    runHook postInstall
  '';
}
