{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  mkAlias = inputs.mkAlias.outputs.apps."aarch64-darwin".default.program;
in {
  disabledModules = ["targets/darwin/linkapps.nix"];
  home.activation.aliasApplications = lib.mkForce (let
    apps = pkgs.buildEnv {
      name = "home-manager-applications";
      paths = config.home.packages;
      pathsToLink = "/Applications";
    };
  in
    lib.hm.dag.entryAfter ["linkGeneration"]
    "	echo \"Linking Home Manager applications...\" 2>&1\n	app_path=\"$HOME/Applications/Home Manager Apps\"\n	tmp_path=\"$(mktemp -dt \"home-manager-applications.XXXXXXXXXX\")\" || exit 1\n	${pkgs.fd}/bin/fd \\\n		-t l -d 1 . ${apps}/Applications \\\n		-x $DRY_RUN_CMD ${mkAlias} -L {} \"$tmp_path/{/}\"\n	$DRY_RUN_CMD rm -rf \"$app_path\"\n	$DRY_RUN_CMD mv \"$tmp_path\" \"$app_path\"\n");
}
