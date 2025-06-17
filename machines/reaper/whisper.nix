{ ... }:
let
  localPort = 10300;
  remotePort = 10299;
in
{
  services = {
    nginx.streamConfig = (
      let
        upstreamName = "wyoming_whisper";
      in
      ''
        upstream ${upstreamName} {
          server 127.0.0.1:${toString localPort};
        }

        server {
          listen ${toString remotePort};
          proxy_pass           ${upstreamName};
          proxy_socket_keepalive on;
        }
      ''
    );
    wyoming = {
      faster-whisper = {
        servers.hass = {
          enable = true;
          uri = "tcp://127.0.0.1:${toString localPort}";
          model = "large-v3";
          language = "en";
          device = "cuda";
        };
      };
    };
  };
  networking.firewall.allowedTCPPorts = [ remotePort ];
}
