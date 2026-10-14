# Native owner-only tool. This is source configuration: apply only via approved
# OpenClaw host control/operator bootstrap, never an agent exec/restart workaround.
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
  state = "/var/lib/nixos-control";
  node = "${pkgs.nodejs_24}/bin/node";
  controller = lib.getExe config.system.build.nixosSwitch;
  package = pkgs.runCommand "openclaw-nixos-control-0.1.0" { } ''
        mkdir -p $out/share/openclaw-plugin-nixos-control $out/bin
        cp ${source}/*.mjs ${source}/package.json ${source}/openclaw.plugin.json ${source}/README.md $out/share/openclaw-plugin-nixos-control/
        substituteInPlace $out/share/openclaw-plugin-nixos-control/host.mjs \
          --replace-fail '@STATE@' '${state}' \
          --replace-fail '@CONTROLLER@' '${controller}' \
          --replace-fail '@SYSTEMD_RUN@' '${pkgs.systemd}/bin/systemd-run' \
          --replace-fail '@SYSTEMCTL@' '${pkgs.systemd}/bin/systemctl' \
          --replace-fail '@PATH@' '${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.systemd
              config.nix.package
            ]
          }'
        substituteInPlace $out/share/openclaw-plugin-nixos-control/transport.mjs \
          --replace-fail '@HOST@' "$out/bin/nixos-control-host" \
          --replace-fail '@PATH@' '${lib.makeBinPath [ pkgs.coreutils ]}'
        cat > $out/bin/nixos-control-host <<EOF
    #!${pkgs.runtimeShell}
    set -euo pipefail
    exec ${pkgs.util-linux}/bin/flock --exclusive --wait 10 ${state}/admission.lock \
      ${node} $out/share/openclaw-plugin-nixos-control/host.mjs "\$@"
    EOF
        chmod +x $out/bin/nixos-control-host
        mkdir -p $out/share/openclaw-plugin-nixos-control/node_modules
        ln -s ${gw.package}/lib/openclaw $out/share/openclaw-plugin-nixos-control/node_modules/openclaw
        cd $out/share/openclaw-plugin-nixos-control
        ${node} --check index.mjs
        ${node} --test *.test.mjs
        # Import SDK and register only against mocks; never start a host service.
        ${node} integration-check.mjs
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
    systemd.tmpfiles.rules = [ "d ${state} 0700 root root -" ];
    security.sudo.extraRules = [
      {
        users = [ gw.user ];
        commands = [
          {
            command = "${package}/bin/nixos-control-host *";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
    my.openclaw.pluginPaths = [ "${package}/share/openclaw-plugin-nixos-control" ];
    services.openclaw-gateway.config = {
      plugins.entries.nixos-control.enabled = true;
      # Add to existing profile, do not replace tools.allow or any deny policy.
      tools.alsoAllow = [
        "nixos_control"
        "nixos_control_status"
      ];
    };
    system.build.nixosControl = package;
  };
}
