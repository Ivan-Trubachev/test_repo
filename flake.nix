{
  description = "newracom-flake";

  outputs = _: {
      mwifiex = import ./mwifiex;
  };
}
