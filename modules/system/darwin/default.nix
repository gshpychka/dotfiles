{ inputs, ... }:
{
  imports = [
    ../../common
    ../common
    # import-tree imports this tree's modules; matchNot drops this default.nix entry point
    (inputs.import-tree.matchNot "/default\\.nix" ./.)
  ];
}
