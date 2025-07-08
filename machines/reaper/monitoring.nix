{ config, ... }:
{
  my.glances = {
    enable = true;
    networkInterfaces = [ config.networking.interfaces.eno3.name ];
    filesystems = [ "/" ];
  };

  # Add nginx reverse proxy for glances
  services.nginx.virtualHosts."glances.${config.networking.fqdn}" = {
    useACMEHost = config.networking.fqdn;
    onlySSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.glances.port}/";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}

