# Access to the gateway: HTTP on loopback behind the host's reverse proxy,
# authenticated by the gateway secret or by the proxy's identity header.
#
# Imperative, one-time without trustedProxy: a browser reaching the Control UI
# through the proxy is a remote device and must be paired from the host:
#   openclaw devices list / openclaw devices approve <id>
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  # the variable OpenClaw's clients read for the shared secret in each auth mode
  secretVar =
    if cfg.trustedProxy.enable then "OPENCLAW_GATEWAY_PASSWORD" else "OPENCLAW_GATEWAY_TOKEN";
  publicOrigin = "https://${cfg.publicHost}";
in
{
  options.my.openclaw = {
    publicHost = lib.mkOption {
      type = lib.types.str;
      description = "HTTPS host name the Control UI is served from.";
    };

    trustedProxy = {
      enable = lib.mkEnableOption ''
        identity from the reverse proxy: requests carrying userHeader from
        gateway.trustedProxies sign in as that user, and their browsers enroll
        without pairing'';
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
      per request, as the owner, for any client holding the gateway secret'';

    localUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString gw.port}";
      readOnly = true;
      description = "Base URL of the gateway's HTTP endpoints on this host.";
    };

    secretFile = lib.mkOption {
      type = lib.types.str;
      default = cfg.secretFiles.${secretVar};
      readOnly = true;
      description = "File holding the gateway secret, sopsFile's gateway-token: the bearer credential of its HTTP endpoints, readable by root only.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.openclaw.secrets.${secretVar} = "gateway-token";

    services.openclaw-gateway = {
      environment.OPENCLAW_DISABLE_BONJOUR = "1";
      config = {
        gateway = {
          mode = "local";
          bind = "loopback";
          inherit (gw) port;
          auth =
            if cfg.trustedProxy.enable then
              {
                mode = "trusted-proxy";
                # clients that bypass the proxy, such as the operator CLI
                password = cfg.secretRefs.${secretVar};
                trustedProxy = {
                  inherit (cfg.trustedProxy) userHeader;
                  allowUsers = cfg.trustedProxy.users;
                  # the proxy connects over loopback, so every local process that
                  # can reach the port can assert an identity
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
          # nginx proxies the Control UI from loopback
          trustedProxies = [ "127.0.0.1" ];
          inherit publicOrigin;
          controlUi = {
            allowedOrigins = [ publicOrigin ];
            automaticallyFetchFavicons = false;
          };
          http.endpoints.responses.enabled = cfg.responsesEndpoint.enable;
          tailscale.mode = "off";
        };
        discovery.mdns.mode = "off";
      };
    };
  };
}
