{
  description = "flake2";

  outputs = _: {
    nixosModules = {
      flake2-pkg = import ./hello_world2;
    };
  };
}
