{
  description = "newracom-flake";

  outputs = _: {
      nrc-driver = import ./nrc-driver;
      nrc-utils = import ./nrc-utils;
  };
}
