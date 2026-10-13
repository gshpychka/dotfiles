{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.cachePrune;
in
{
  options.my.cachePrune = {
    enable = lib.mkEnableOption "weekly pruning of package manager caches";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.cache-prune = {
      Unit.Description = "Prune package manager caches";
      Service = {
        Type = "oneshot";
        ExecStart = [
          # remove packages no project references from pnpm 10's store
          "${lib.getExe pkgs.pnpm_10} store prune"
          # remove packages no project references from pnpm 11's store
          "${lib.getExe pkgs.pnpm_11} store prune"
          # remove the npm download cache
          "${lib.getExe' pkgs.nodejs "npm"} cache clean --force"
          # remove the yarn v1 download cache
          "${lib.getExe pkgs.yarn} cache clean"
          # remove uv cache entries nothing reaches
          "${lib.getExe pkgs.uv} cache prune"
        ];
      };
    };

    systemd.user.timers.cache-prune = {
      Unit.Description = "Prune package manager caches weekly";
      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
