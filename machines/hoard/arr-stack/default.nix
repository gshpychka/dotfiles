{
  ...
}:
{
  imports = [
    ./recyclarr.nix
    ./maintainerr.nix
    ./auth.nix
    ./sync.nix
  ];

  services = {
    prowlarr = {
      enable = true;
    };
    sonarr = {
      enable = true;
      group = "media";
    };
    radarr = {
      enable = true;
      group = "media";
    };
    lidarr = {
      enable = true;
      group = "media";
    };
    bazarr = {
      enable = true;
      group = "media";
      # Bazarr's auth setting lives in its stateful config.yaml. One-time UI
      # step: Settings → General → Security → Authentication = None; the web
      # gateway owns interactive auth and /api keeps requiring X-API-KEY.
    };
    overseerr = {
      enable = true;
    };
  };
}
