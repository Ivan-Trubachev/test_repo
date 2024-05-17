{
  description = "nixos-software";

  outputs = _: {
    nixosModules = {
      osf = import ./osf;
    };
  };
}
