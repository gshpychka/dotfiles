{ lib, ... }:
# Global configuration options and values.
{
  options.my = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "glib.sh";
      description = "Public domain name";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "gshpychka";
      description = "Main username";
    };
    sshKeys = lib.mkOption {
      type = lib.types.submodule {
        options = {
          main = lib.mkOption {
            type = lib.types.str;
            description = "Main SSH public key";
          };
          homeassistant = lib.mkOption {
            type = lib.types.str;
            description = "SSH public key for home assistant";
          };
          gitlab = lib.mkOption {
            type = lib.types.str;
            description = "SSH public key for GitLab";
          };
        };
      };
      description = "SSH public keys";
    };
    nixbuildKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "SSH public keys for distributed builds";
    };
    buildServers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hostName = lib.mkOption {
              type = lib.types.str;
              description = "Hostname to connect to";
            };
            systems = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Supported systems";
            };
            maxJobs = lib.mkOption {
              type = lib.types.ints.positive;
              description = "Maximum concurrent jobs";
            };
            speedFactor = lib.mkOption {
              type = lib.types.ints.positive;
              description = "Relative speed factor";
            };
            supportedFeatures = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Supported features";
            };
            mandatoryFeatures = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Mandatory features";
            };
            sshUser = lib.mkOption {
              type = lib.types.str;
              description = "Username for builds";
            };
          };
        }
      );
      default = { };
      description = "Build server configurations";
    };
  };
  config = {
    my.sshKeys = {
      main = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG";
      homeassistant = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAC9nquQBUuHWrWJvuUJLuR2zfupJp+QtQlpck0n5J0J";
      gitlab = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK0TQf0piikNdo54HRg/l6dBXRPM2BmlA4f7EmXJ9uvW";
    };
    my.nixbuildKeys = {
      eve = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP7jjV4iQfoCWZYWw2Q1bdsNg6PBc4U2SclLE2Wil0b9 nixbuild-eve@eve";
      hoard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFy/oQXrAZW1aGN6w9RpXBREZ7jvZid2hO508mw8x0yT nixbuild-hoard@hoard";
      harbor = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABSB7E2A8KEVWo5u+fDHa74I16/1UcukAZps6902H3r nixbuild-harbor@harbor";
    };
    my.buildServers = {
      reaper = {
        hostName = "reaper";
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        maxJobs = 16;
        speedFactor = 4;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        mandatoryFeatures = [ ];
        sshUser = "nixbuild";
      };
    };
    time.timeZone = "Europe/Kyiv";
  };
}
