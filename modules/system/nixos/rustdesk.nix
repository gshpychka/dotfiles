{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.rustdesk-server;

  # https://github.com/NixOS/nixpkgs/blob/ae814fd3904b621d8ab97418f1d0f2eb0d3716f4/nixos/modules/services/monitoring/rustdesk-server.nix#L6:L15
  TCPPorts = [
    21115
    21116
    21117
    21118
    21119
  ];
  UDPPorts = [ 21116 ];

  # hbbs/hbbr take `-k <key-string>`, NOT a key file path: any value that
  # isn't a base64 ed25519 key is enforced as the literal key clients must
  # present. The only file-based mechanism they support is reading
  # `id_ed25519` from their working directory when started with `-k _`
  # (which also rejects clients that don't present the matching public key).
  # So: hand the secret to each daemon via systemd credentials (the sops
  # file stays root-owned; LoadCredential makes it readable to the
  # unprivileged service user), install it as id_ed25519 in the shared
  # state directory, and start with `-k _`.
  keyArgs = lib.optionals (cfg.privateKeyFile != null) [
    "-k"
    "_"
  ];

  # Both daemons must install the key themselves: whichever starts first
  # would otherwise generate its own keypair into the shared state dir and
  # enforce that instead. The tmp+mv dance keeps the other daemon from ever
  # reading a half-written file.
  keyService = lib.mkIf (cfg.privateKeyFile != null) {
    serviceConfig.LoadCredential = [ "id_ed25519:${cfg.privateKeyFile}" ];
    path = [ pkgs.coreutils ];
    # runs in WorkingDirectory (/var/lib/rustdesk), as the service user
    preStart = ''
      install -m 0400 "$CREDENTIALS_DIRECTORY/id_ed25519" id_ed25519.tmp
      mv -f id_ed25519.tmp id_ed25519
    '';
  };
in
{
  options.my.rustdesk-server = {
    enable = lib.mkEnableOption "RustDesk server";

    relayHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Relay server addresses handed to clients by the signal server.
        Every client must be able to resolve and reach them on port 21117.
      '';
      example = [ "100.x.x.x" ];
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the server's ed25519 private key (the base64 "Secret Key"
        line from `rustdesk-utils genkeypair`), managed via sops. When set,
        clients must be configured with the matching public key.
      '';
    };

    tailscaleOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Only allow connections via Tailscale interface";
    };
  };

  config = lib.mkIf cfg.enable {
    services.rustdesk-server = {
      enable = true;
      openFirewall = false;
      signal = {
        enable = true;
        inherit (cfg) relayHosts;
        extraArgs = keyArgs;
      };
      relay = {
        enable = true;
        extraArgs = keyArgs;
      };
    };

    systemd.services.rustdesk-signal = keyService;
    systemd.services.rustdesk-relay = keyService;

    # Custom firewall configuration
    networking.firewall = lib.mkMerge [
      (lib.mkIf (!cfg.tailscaleOnly) {
        allowedTCPPorts = TCPPorts;
        allowedUDPPorts = UDPPorts;
      })
      (lib.mkIf cfg.tailscaleOnly {
        interfaces.${config.services.tailscale.interfaceName} = {
          allowedTCPPorts = TCPPorts;
          allowedUDPPorts = UDPPorts;
        };
      })
    ];
  };
}
