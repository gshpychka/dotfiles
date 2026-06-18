{ inputs, ... }:
{
  # import-tree imports this tree's modules; matchNot drops this default.nix entry point
  imports = [ (inputs.import-tree.matchNot "/default\\.nix" ./.) ];
}
