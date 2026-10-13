# Access to the gateway: HTTP on loopback behind the host's reverse proxy,
# authenticated by the gateway secret or by the proxy's identity header.
#
# Imperative, one-time: generate the gateway secret:
#   openssl rand -hex 32 | jq -R . | sops set --value-stdin <sopsFile> '["gateway-token"]'
#
# Imperative, per browser while trustedProxy is off: approve its pairing
# request from the host:
#   openclaw devices list
#   openclaw devices approve <requestId>
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  # the variable OpenClaw reads the gateway secret from in each auth mode
  secretVar =
    if cfg.trustedProxy.enable then "OPENCLAW_GATEWAY_PASSWORD" else "OPENCLAW_GATEWAY_TOKEN";
in
{
  options.my.openclaw = {
    publicHost = lib.mkOption {
      type = lib.types.str;
      description = "HTTPS host name the gateway is reached at through the reverse proxy.";
    };

    trustedProxy = {
      enable = lib.mkEnableOption ''
        identity from the host's reverse proxy: a request carrying userHeader
        signs in as that user, and its browser enrolls without pairing. Any
        local process that reaches the gateway port can claim a user, so the
        host limits who reaches it'';
      userHeader = lib.mkOption {
        type = lib.types.str;
        description = "Request header the proxy sets to the signed-in user's name.";
      };
      users = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        description = "Proxy-authenticated users admitted, each as an administrator.";
      };
    };

    responsesEndpoint.enable = lib.mkEnableOption ''
      the OpenResponses endpoint, POST /v1/responses
      (https://docs.openclaw.ai/gateway/openresponses-http-api): one agent turn
      per request, as the owner, for clients on this host holding the gateway
      secret'';

    localUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString gw.port}";
      readOnly = true;
      description = "Base URL of the gateway's HTTP endpoints on this host.";
    };

    gatewaySecretFile = lib.mkOption {
      type = lib.types.str;
      default = cfg.secretFiles.${secretVar};
      readOnly = true;
      description = "File holding the gateway secret, the bearer credential of its HTTP endpoints, readable by root only.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.openclaw.secrets.${secretVar} = "gateway-token";

    services.openclaw-gateway.config = {
      gateway = {
        bind = "loopback";
        inherit (gw) port;
        auth =
          if cfg.trustedProxy.enable then
            {
              mode = "trusted-proxy";
              # clients that bypass the proxy
              password = cfg.secretRefs.${secretVar};
              trustedProxy = {
                inherit (cfg.trustedProxy) userHeader;
                allowUsers = cfg.trustedProxy.users;
                allowLoopback = true;
                deviceAutoApprove.enabled = true;
              };
              identityScopes = lib.genAttrs cfg.trustedProxy.users (_: [ "operator.admin" ]);
            }
          else
            {
              mode = "token";
              token = cfg.secretRefs.${secretVar};
            };
        # the host's reverse proxy connects from loopback
        trustedProxies = [ "127.0.0.1" ];
        publicOrigin = "https://${cfg.publicHost}";
        # the Control UI shows links without fetching their pages
        controlUi.automaticallyFetchFavicons = false;
        http.endpoints.responses.enabled = cfg.responsesEndpoint.enable;
      };
      discovery.mdns.mode = "off";
    };
  };
}
