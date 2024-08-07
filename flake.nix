{
  description = "nxp-flake";

  outputs = _: {
      mwifiex = import ./mwifiex;
      plug-and-trust = import ./plug-and-trust;
  };
}
