{
  description = "newracom-flake";

  outputs = _: {
      nrc_driver = import ./nrc-driver;
      nrc_utils = import ./nrc-utils;
  };
}
