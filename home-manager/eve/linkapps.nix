{
	config,
	inputs,
	lib,
	pkgs,
	...
}:
let
	mkAlias = inputs.mkAlias.outputs.apps."aarch64-darwin".default.program;
in {
	disabledModules = ["targets/darwin/linkapps.nix"];
	home.activation.aliasApplications =
		lib.mkForce (
			let
				apps = pkgs.buildEnv {
					name = "home-manager-applications";
					paths = config.home.packages;
					pathsToLink = "/Applications";
				};
			in lib.hm.dag.entryAfter ["linkGeneration"] ''
				echo "Linking Home Manager applications..." 2>&1
				app_path="$HOME/Applications/Home Manager Apps"
				tmp_path="$(mktemp -dt "home-manager-applications.XXXXXXXXXX")" || exit 1
				${pkgs.fd}/bin/fd \
					-t l -d 1 . ${apps}/Applications \
					-x $DRY_RUN_CMD ${mkAlias} -L {} "$tmp_path/{/}"
				$DRY_RUN_CMD rm -rf "$app_path"
				$DRY_RUN_CMD mv "$tmp_path" "$app_path"
			''
		);
}
