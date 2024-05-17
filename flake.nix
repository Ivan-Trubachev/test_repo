{
  description = "osf-nixpkg";

  outputs = _: {
    nixosModules = {
      osf = import ./osf;
    };
  };
}
