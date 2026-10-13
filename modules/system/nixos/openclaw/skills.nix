# Skills (https://docs.openclaw.ai/tools/skills) the agent reads when a task
# matches their description.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;

  # one directory per skill, holding real files: the loader skips symlinks that leave their root
  skillDirs = lib.mapAttrsToList (
    name: skill:
    toString (
      pkgs.writeTextFile {
        name = "openclaw-skill-${name}";
        destination = "/${name}/SKILL.md";
        text = ''
          ---
          name: ${name}
          description: ${lib.generators.toYAML { } skill.description}
          ---
          ${skill.text}'';
      }
    )
  ) cfg.skills;

  # extraDirs is the lowest-precedence skill source; a bundled skill of the same name wins
  skillsCheck =
    pkgs.runCommand "openclaw-skills-check"
      {
        env = {
          OPENCLAW_NIX_MODE = "1";
          OPENCLAW_CONFIG_PATH = pkgs.writeText "openclaw-skills.json" (
            builtins.toJSON { skills.load.extraDirs = skillDirs; }
          );
        };
      }
      ''
        # a writable home and state directory for the CLI, inside the build's scratch directory
        export HOME=$TMPDIR OPENCLAW_STATE_DIR=$TMPDIR/state
        # the skills the gateway loads, each with its source, as JSON in $out
        ${lib.getExe gw.package} skills list --json > $out
        # fails the build (-e) unless every configured skill loads from extraDirs (source openclaw-extra)
        ${lib.getExe pkgs.jq} -e --argjson names '${builtins.toJSON (lib.attrNames cfg.skills)}' \
          '$names - [.skills[] | select(.source == "openclaw-extra") | .name] == []' $out
      '';
in
{
  options.my.openclaw.skills = lib.mkOption {
    default = { };
    description = "Skills the agent gets, keyed by skill name: lowercase letters, digits and hyphens.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "What the skill is for, listed in every prompt.";
          };
          text = lib.mkOption {
            type = lib.types.lines;
            description = "The skill's instructions, which the agent reads when its task matches the description.";
          };
        };
      }
    );
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway.config.skills.load.extraDirs = skillDirs;
    system.checks = [ skillsCheck ];
  };
}
