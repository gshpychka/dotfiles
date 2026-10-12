# MCP servers (https://docs.openclaw.ai/tools/mcp) whose tools the agent gets.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  enabledServers = lib.filterAttrs (_: server: server.enable) cfg.mcpServers;
in
{
  options.my.openclaw.mcpServers = lib.mkOption {
    default = { };
    description = "MCP servers whose tools the agent gets, keyed by server name.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether the server is connected; its secrets must exist in sopsFile while it is.";
          };
          settings = lib.mkOption {
            inherit (pkgs.formats.json { }) type;
            description = "The server's mcp.servers entry, a url or a command. Strings reference secrets as \${NAME}.";
          };
          secrets = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            example = {
              HOME_ASSISTANT_TOKEN = "home-assistant-token";
            };
            description = "Environment variables for \${NAME} references in settings, each set from the named sopsFile key.";
          };
        };
      }
    );
  };

  config = lib.mkIf cfg.enable {
    my.openclaw.secrets = lib.concatMapAttrs (_: server: server.secrets) enabledServers;
    services.openclaw-gateway.config.mcp.servers = lib.mapAttrs (
      _: server: server.settings
    ) enabledServers;
  };
}
