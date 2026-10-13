# VM test of nixos-switch (modules/system/nixos/nixos-switch.nix) with the
# OpenClaw gateway's readiness gate (modules/system/nixos/openclaw/gateway.nix):
# a switch that restarts the gateway, a rollback after a gateway that never
# becomes ready, and checks and builds that fail without changing the
# generation, the running system or the boot loader.
#   nix build .#checks.x86_64-linux.nixos-switch
#
# The VM reaches neither GitHub nor a builder, so it switches to prebuilt
# toplevels with the activation `nixos-switch switch` runs after its build, and
# takes its commits from a repository it makes itself.
{ inputs, pkgs }:
let
  # the gateway secret in a sops file, with the age key that decrypts it
  sops =
    pkgs.runCommand "nixos-switch-test-sops"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.sops
        ];
      }
      ''
        mkdir $out
        age-keygen -o $out/age-key.txt
        echo 'gateway-token: test-gateway-token' > secrets.yaml
        sops encrypt --age "$(age-keygen -y $out/age-key.txt)" secrets.yaml > $out/secrets.yaml
      '';

  # A flake.nix of the VM's repository, whose toplevel any machine could build:
  # with --max-jobs 0 only a builder may, and the VM reaches none.
  flake =
    inputs:
    pkgs.writeText "flake.nix" ''
      {
        inputs = ${inputs};
        outputs = _: {
          nixosConfigurations.machine.config.system.build.toplevel = derivation {
            name = "toplevel";
            system = "x86_64-linux";
            builder = "/bin/sh";
            args = [ "-c" "echo > $out" ];
          };
        };
      }
    '';
in
inputs.nixpkgs.lib.nixos.runTest {
  name = "nixos-switch";
  hostPkgs = pkgs;
  node.specialArgs = { inherit inputs; };

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        ../modules/system/nixos
      ];

      virtualisation = {
        memorySize = 4096;
        cores = 4;
        # The ESP the test makes, for hoard's boot loader. The VM boots its
        # kernel directly instead: the disk image useBootLoader builds runs
        # out of inodes on the gateway's closure.
        emptyDiskImages = [ 512 ];
      };
      boot.loader.systemd-boot.enable = true;

      sops = {
        # the file is a build output, which evaluation does not read
        validateSopsFiles = false;
        # sops-nix refuses a key in the store, so activation copies it out first
        age.keyFile = "/var/lib/sops-nix/key.txt";
        age.sshKeyPaths = [ ];
        gnupg.sshKeyPaths = [ ];
      };
      system.activationScripts = {
        testAgeKey = "install -D -m 400 ${sops}/age-key.txt /var/lib/sops-nix/key.txt";
        setupSecrets.deps = [ "testAgeKey" ];
      };
      my.openclaw = {
        enable = true;
        sopsFile = "${sops}/secrets.yaml";
        publicHost = "openclaw.test";
        model.primary = "openai/test";
      };

      my.nixosSwitch = {
        enable = true;
        repository = "file:///tmp/origin.git";
      };
      # hoard's builder, which the VM cannot reach
      nix = {
        distributedBuilds = true;
        buildMachines = [
          {
            hostName = "reaper";
            sshUser = "nixbuild";
            system = "x86_64-linux";
            protocol = "ssh";
          }
        ];
        settings.substituters = lib.mkForce [ ];
      };
      environment.systemPackages = [
        pkgs.git
        pkgs.gptfdisk
        pkgs.dosfstools
      ];

      specialisation = {
        # a change to the gateway's unit, so the switch restarts it
        good.configuration.services.openclaw-gateway.environment.NIXOS_SWITCH_TEST = "good";
        # a gateway that runs and never becomes ready
        unready.configuration = {
          services.openclaw-gateway.execStart = "${pkgs.coreutils}/bin/sleep infinity";
          systemd.services.openclaw-gateway.serviceConfig.TimeoutStartSec = lib.mkForce 30;
        };
      };
    };

  testScript =
    { nodes, ... }:
    let
      toplevel = nodes.machine.system.build.toplevel;
      activate = lib.getExe nodes.machine.system.build.nixosSwitchActivate;
      inherit (pkgs) lib;
    in
    ''
      good = "${nodes.machine.specialisation.good.configuration.system.build.toplevel}"
      unready = "${nodes.machine.specialisation.unready.configuration.system.build.toplevel}"


      def state():
          """The generation, the running system and the boot loader's default and entries."""
          return machine.succeed(
              "readlink /nix/var/nix/profiles/system"
              " && readlink -f /run/current-system"
              " && grep ^default /boot/loader/loader.conf"
              " && cd /boot/loader/entries && sha256sum *"
          )


      def activate(system):
          """The activation `nixos-switch switch` runs once it has built a toplevel."""
          return machine.execute(
              "systemd-run --unit=nixos-switch --service-type=exec --collect --wait --quiet"
              f" ${activate} {system}"
          )[0]


      def switch(sha):
          return machine.execute(f"nixos-switch switch {sha} 2>&1")


      def boots(generation):
          """Whether the boot loader defaults to the generation."""
          machine.succeed(
              "entry=$(sed -n 's/^default //p' /boot/loader/loader.conf)"
              f" && grep -F 'version Generation {generation} ' /boot/loader/entries/$entry*"
          )


      machine.wait_for_unit("multi-user.target")
      # generation 1, the booted system, installed with its boot loader on a new ESP
      machine.succeed(
          "sgdisk --new=1:0:0 --typecode=1:EF00 /dev/vdb",
          "udevadm settle",
          "mkfs.vfat /dev/vdb1",
          "mkdir -p /boot && mount /dev/vdb1 /boot",
          "nix-env --profile /nix/var/nix/profiles/system --set ${toplevel}",
          "NIXOS_INSTALL_BOOTLOADER=1 ${toplevel}/bin/switch-to-configuration boot",
      )
      boots(1)

      with subtest("the gateway starts once ready and authenticated"):
          machine.wait_for_unit("openclaw-gateway.service")
          machine.succeed("journalctl -u openclaw-gateway -o cat | grep -F 'Gateway Health'")
          machine.succeed("openclaw gateway health")
          machine.fail("openclaw gateway health --token wrong-token")

      with subtest("a switch restarts the gateway, which drains on stop and passes readiness on start"):
          assert activate(good) == 0
          machine.succeed(f'test "$(readlink -f /run/current-system)" = {good}')
          machine.succeed("test $(readlink /nix/var/nix/profiles/system) = system-2-link")
          boots(2)
          machine.succeed("systemctl show -p Environment openclaw-gateway | grep -F NIXOS_SWITCH_TEST=good")
          # the stopped gateway took its drain budget from the unit, and drained
          machine.succeed("journalctl -u openclaw-gateway -o cat | grep 'shutdown budget at shutdown' | grep -F TimeoutStopUSec=330000ms")
          machine.succeed("journalctl -u openclaw-gateway -o cat | grep -F 'active-work drain settled'")
          switched = state()

      with subtest("a gateway that never becomes ready fails the switch, which returns to the exact prior state"):
          assert activate(unready) == 1
          assert state() == switched, "rollback changed the generation, the running system or the boot loader"
          machine.fail("test -e /nix/var/nix/profiles/system-3-link")
          # switch-to-configuration failed on the gateway's start alone
          journal = machine.succeed("journalctl --unit=nixos-switch --invocation=0 --output=cat")
          assert "Failed to start openclaw-gateway.service" in journal, journal
          assert "activation failed with exit status 4" in journal, journal
          machine.wait_for_unit("openclaw-gateway.service")
          machine.succeed("systemctl show -p Environment openclaw-gateway | grep -F NIXOS_SWITCH_TEST=good")

      with subtest("failed checks and builds change nothing"):
          machine.succeed("""
            set -eu
            export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
            git init --quiet /tmp/dep
            git -C /tmp/dep commit --quiet --allow-empty -m dep
            git init --quiet --initial-branch=main /tmp/work
            cd /tmp/work
            cp ${flake "{ }"} flake.nix
            echo '{"nodes":{"root":{}},"root":"root","version":7}' > flake.lock
            git add flake.nix flake.lock
            git commit --quiet -m unbuildable
            git rev-parse HEAD > /tmp/unbuildable
            git switch --quiet --create side
            git commit --quiet --allow-empty -m side
            git rev-parse HEAD > /tmp/side
            git switch --quiet main
            # an input the committed flake.lock does not pin
            cp ${flake ''{ dep = { url = "git+file:///tmp/dep"; flake = false; }; }''} flake.nix
            git commit --quiet --all -m unlocked
            git rev-parse HEAD > /tmp/unlocked
            git clone --quiet --bare /tmp/work /tmp/origin.git
          """)
          cases = {
              "side": "is not on main",
              "unlocked": "cannot write modified lock file",
              "unbuildable": "local builds are disabled (max-jobs = 0)",
          }
          for commit, error in cases.items():
              sha = machine.succeed(f"cat /tmp/{commit}").strip()
              status, output = switch(sha)
              print(output)
              assert status == 1, f"{commit}: exit status {status}"
              assert error in output, f"{commit}: no {error!r} in the output"
              assert state() == switched, f"{commit}: the failed switch changed the system"
          status, output = switch("0" * 40)
          assert status == 1 and "is not on main" in output, output
          status, _ = switch("HEAD")
          assert status == 64
          assert state() == switched
    '';
}
