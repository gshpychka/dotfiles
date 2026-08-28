{
  importNpmLock,
  lib,
  nodejs,
  writeShellApplication,
  writeText,
  git,
}:
# The pinned pi package set. package-lock.json is generated: `nix run .#update-pi-packages`
# resolves every package below to its latest version.
let
  # attribute name -> npm package, since scoped names collide across publishers
  packages = {
    pi-ask-user-question = "@juicesharp/rpiv-ask-user-question";
    pi-lens = "pi-lens";
    pi-mcp-adapter = "pi-mcp-adapter";
    pi-permission-system = "@gotgenes/pi-permission-system";
    pi-plan-mode = "@narumitw/pi-plan-mode";
    pi-rewind = "pi-rewind";
    pi-statusline = "@narumitw/pi-statusline";
    pi-subagents = "@gotgenes/pi-subagents";
    pi-todo = "@juicesharp/rpiv-todo";
    pi-web-access = "pi-web-access";
  };
  manifest = {
    name = "pi-packages";
    version = "0.0.0";
    private = true;
    dependencies = lib.genAttrs (lib.attrValues packages) (_: "*");
  };
  lock = lib.importJSON ./package-lock.json;
  unlocked = lib.subtractLists (lib.attrNames lock.packages."".dependencies) (
    lib.attrValues packages
  );
  tree = importNpmLock.buildNodeModules {
    package = manifest;
    packageLock = lock;
    inherit nodejs;
    # pi hands @earendil-works/* to extensions at load, so those peers stay out of the tree
    derivationArgs.npmFlags = [ "--legacy-peer-deps" ];
  };
in
{
  inherit tree;
  # each package resolves its own dependencies from the enclosing node_modules
  sources = lib.throwIf (unlocked != [ ]) ''
    pi-packages: ${lib.concatStringsSep ", " unlocked} missing from package-lock.json.
    Run `nix run .#update-pi-packages`.
  '' (lib.mapAttrs (_: npmName: "${tree}/node_modules/${npmName}") packages);

  updateScript = writeShellApplication {
    name = "update-pi-packages";
    runtimeInputs = [
      nodejs
      git
    ];
    text = ''
      lock="$(git rev-parse --show-toplevel)/packages/pi-packages/package-lock.json"
      work="$(mktemp -d)"
      trap 'rm -rf "$work"' EXIT
      cp ${writeText "package.json" (builtins.toJSON manifest)} "$work/package.json"
      cd "$work"
      npm install --package-lock-only --legacy-peer-deps --no-audit --no-fund
      cp package-lock.json "$lock"
    '';
  };
}
