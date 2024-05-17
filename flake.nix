{
  description = "osf-package";

  outputs = _: {
    nixosModules = {
      osf = import ./osf;
    };
  };
}
