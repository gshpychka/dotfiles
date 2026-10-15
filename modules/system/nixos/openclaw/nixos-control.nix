# Owner-only native shim; deployment stays in the existing nixos-switch engine.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw.nixosControl;
  gw = config.services.openclaw-gateway;
  source = ../../../../scripts/nixos-control;
  node = "${pkgs.nodejs_24}/bin/node";
  # The controller detaches activation only, not its preceding fetch/build.
  # Keep the entire existing command outside the Gateway cgroup.
  helper = pkgs.writeShellScript "nixos-control-start" ''
    exec ${pkgs.systemd}/bin/systemd-run --unit=nixos-control --service-type=exec --collect \
      -- ${lib.getExe config.system.build.nixosSwitch} "$@"
  '';
  package = pkgs.runCommand "openclaw-nixos-control-0.2.0" { } ''
    dest=$out/share/openclaw-plugin-nixos-control
    mkdir -p "$dest/node_modules"
    cp ${source}/* "$dest/"
    substituteInPlace "$dest/index.mjs" --replace-fail '@HELPER@' '${helper}'
    ln -s ${gw.package}/lib/openclaw "$dest/node_modules/openclaw"
    cd "$dest"
    ${node} --check index.mjs
    ${node} --test index.test.mjs
  '';
in
{
  options.my.openclaw.nixosControl.enable =
    lib.mkEnableOption "owner-only native NixOS build/switch control";
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.openclaw.enable && config.my.nixosSwitch.enable;
        message = "nixosControl needs the Gateway and existing nixos-switch controller.";
      }
      {
        assertion = gw.user == "openclaw" && config.networking.hostName == "hoard";
        message = "nixosControl is explicitly scoped to hoard's openclaw service identity.";
      }
    ];
    security.sudo.extraRules = [
      {
        users = [ gw.user ];
        runAs = "root:root";
        commands = [
          {
            command = "${helper} *";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
    my.openclaw.pluginPaths = [ "${package}/share/openclaw-plugin-nixos-control" ];
    services.openclaw-gateway.config = {
      plugins.entries.nixos-control.enabled = true;
      tools.alsoAllow = [ "nixos_control" ];
    };
    system.build.nixosControl = package;
  };
}
