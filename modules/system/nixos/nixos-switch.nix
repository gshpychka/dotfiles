# `nixos-switch`: switches this host to its configuration at a commit on main
# of the canonical repository, built on the remote builders alone, and returns
# it to the generation it ran before when the activation fails.
#
#   nixos-switch build <full commit sha>         # the checks and the build only
#   sudo nixos-switch switch <full commit sha>
#
# A failed check or build changes nothing on this host. The activation runs in
# the transient unit nixos-switch.service, outside the caller's cgroup, so it
# carries on when a service it restarts, such as the OpenClaw gateway, ran the
# command; its journal (`journalctl -u nixos-switch -I`) shows how it ended.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.nixosSwitch;
  host = config.networking.hostName;
  profile = "/nix/var/nix/profiles/system";
  # systemd refuses to start a second unit of this name while one runs
  unitName = "nixos-switch";

  # Takes a built toplevel. Exits 0 once switched, 1 after a failed activation
  # it rolled back, 2 when a step of that rollback failed too.
  activate = pkgs.writeShellApplication {
    name = "nixos-switch-activate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      config.nix.package
    ];
    text = ''
      toplevel=$1
      # the profile's current generation number, from its link: system-<n>-link
      generation() {
        local link
        link=$(readlink ${profile})
        link=''${link#system-}
        echo "''${link%-link}"
      }

      # what a failed activation returns to: the profile's generation, which
      # the boot menu defaults to, and the running system, which can differ
      prior_generation=$(generation)
      prior_boot=$(readlink -f ${profile})
      prior_runtime=$(readlink -f /run/current-system)
      # the newest generation; one this switch adds is numbered above it
      newest=$(nix-env --profile ${profile} --list-generations | awk 'END { print $1 }')
      echo "switching from generation $prior_generation ($prior_boot), running $prior_runtime, to $toplevel"

      status=0
      { nix-env --profile ${profile} --set "$toplevel" && "$toplevel/bin/switch-to-configuration" switch; } || status=$?
      if ((status == 0)); then
        echo "switched to generation $(generation), $toplevel"
        exit 0
      fi

      echo "activation failed with exit status $status: returning to generation $prior_generation and $prior_runtime" >&2
      # every step runs, whatever the ones before it did; all of them use the local store alone
      failed=0
      added=$(generation)
      nix-env --profile ${profile} --switch-generation "$prior_generation" || failed=1
      if ((added > newest)); then
        nix-env --profile ${profile} --delete-generations "$added" || failed=1
      fi
      "$prior_runtime/bin/switch-to-configuration" test || failed=1
      # the boot loader, reinstalled from the profile: its default and entries as they were
      "$prior_boot/bin/switch-to-configuration" boot || failed=1
      if ((failed)); then
        echo "rollback incomplete: a step above failed" >&2
        exit 2
      fi
      echo "returned to generation $prior_generation and $prior_runtime" >&2
      exit 1
    '';
  };

  nixos-switch = pkgs.writeShellApplication {
    name = "nixos-switch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gitMinimal
      config.nix.package
      config.systemd.package
    ];
    text = ''
      usage() {
        echo "usage: nixos-switch build|switch <full sha of a commit on main of ${cfg.repository}>" >&2
        exit 64
      }
      [ $# -eq 2 ] || usage
      action=$1
      sha=$2
      case $action in build | switch) ;; *) usage ;; esac
      [[ $sha =~ ^[0-9a-f]{40}$ ]] || usage
      if [ "$action" = switch ] && [ "$(id -u)" -ne 0 ]; then
        echo "nixos-switch switch runs as root" >&2
        exit 1
      fi

      # main as the canonical repository has it now, fetched afresh into an
      # empty repository, which holds no commit off it
      history=$(mktemp -d)
      trap 'rm -rf "$history"' EXIT
      git -C "$history" init --quiet --bare
      git -C "$history" fetch --quiet ${cfg.repository} main
      if ! git -C "$history" merge-base --is-ancestor "$sha" FETCH_HEAD; then
        echo "$sha is not on main of ${cfg.repository}" >&2
        exit 1
      fi

      # the commit's tree with its committed flake.lock, which nix does not
      # change: a missing or outdated one fails the build ("cannot write
      # modified lock file" of this immutable source); built on the configured
      # remote builders alone (--max-jobs 0)
      toplevel=$(nix build --no-link --print-out-paths --max-jobs 0 --no-update-lock-file \
        "git+${cfg.repository}?rev=$sha#nixosConfigurations.${host}.config.system.build.toplevel")
      echo "built $toplevel from $sha"
      [ "$action" = switch ] || exit 0

      echo "activating in ${unitName}.service; follow with: journalctl -fu ${unitName}"
      status=0
      systemd-run --unit=${unitName} --service-type=exec --collect --wait --quiet \
        ${lib.getExe activate} "$toplevel" || status=$?
      journalctl --unit=${unitName} --invocation=0 --output=cat --no-pager
      exit "$status"
    '';
  };
in
{
  options.my.nixosSwitch = {
    enable = lib.mkEnableOption "`nixos-switch`, this host's switch to a commit on main of its canonical repository";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/gshpychka/dotfiles.git";
      description = "Git URL of the canonical repository of this configuration, whose main holds the commits `nixos-switch` takes.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nix.distributedBuilds && config.nix.buildMachines != [ ];
        message = "my.nixosSwitch builds on remote builders alone (--max-jobs 0), so it needs nix.buildMachines.";
      }
    ];

    environment.systemPackages = [ nixos-switch ];
    # for tests/nixos-switch.nix, which activates prebuilt toplevels with it
    system.build.nixosSwitchActivate = activate;
  };
}
