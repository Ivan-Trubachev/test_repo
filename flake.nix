{
  description = "newracom-flake";

  outputs = _: {
      nrc_driver = import ./nrc_driver;
  };
}
