{
  description = "flake1";

  outputs = _: {
    nixosModules = {
      flake1-pkg = import ./hello_world1;
    };
  };
}
