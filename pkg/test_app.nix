{
  lib,
  stdenv,
  pkg-config,
  ...
}:
stdenv.mkDerivation rec {
  pname = "test_app";
  version = "v0.1";

  src = ./src;
  nativeBuildInputs = [pkg-config];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ./test_app $out/bin
    runHook postInstall
  '';
}
