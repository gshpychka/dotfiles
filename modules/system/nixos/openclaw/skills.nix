# Skills (https://docs.openclaw.ai/tools/skills): a SKILL.md per set of host
# commands, telling the agent when and how to use them.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;

  skillsDir = pkgs.runCommand "openclaw-skills" { } (
    lib.concatStrings (
      lib.mapAttrsToList (name: skill: ''
        mkdir -p $out/${name}
        cp ${pkgs.writeText "${name}-SKILL.md" ''
          ---
          name: ${name}
          description: ${builtins.toJSON skill.description}
          ---
          ${skill.text}''} $out/${name}/SKILL.md
      '') cfg.skills
    )
  );
in
{
  options.my.openclaw.skills = lib.mkOption {
    default = { };
    description = "Skills describing the agent's host commands, keyed by name.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "One line, under 160 characters, shown to the agent.";
          };
          text = lib.mkOption {
            type = lib.types.lines;
            description = "SKILL.md body: when and how to use the commands.";
          };
        };
      }
    );
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway.config.skills.load.extraDirs = [ "${skillsDir}" ];
  };
}
