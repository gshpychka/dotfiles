{ config, lib, ... }:
# Public face of the fleet's OIDC issuer: the issuer URL and the documents a
# relying party (AWS STS) fetches to verify tokens. Shared because two
# machines need the same values: reaper signs tokens
# (machines/reaper/oidc-issuer) and buoy publishes these documents
# (machines/buoy/oidc-discovery.nix), so reaper itself serves nothing publicly.
let
  cfg = config.my.oidcIssuer;
  # The only key type the signer generates: ECDSA P-256, which AWS accepts as ES256.
  algorithm = "ES256";
in
{
  options.my.oidcIssuer = {
    host = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      # infra/buoy/dns.tf points this name at buoy's tunnel
      default = "tokens.${config.my.domain}";
      description = "Public hostname of the issuer.";
    };
    url = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://${cfg.host}";
      description = ''
        Issuer identifier: the `iss` claim, and the provider URL AWS is
        configured with. AWS fetches `<url>` + `discoveryPath`.
      '';
    };
    audience = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      # the audience GitHub Actions and the AWS docs use for STS
      default = "sts.amazonaws.com";
      description = "`aud` claim of every token; the client ID registered with the AWS OIDC provider.";
    };
    discoveryPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      # fixed by OIDC Discovery; AWS appends it to the issuer URL
      default = "/.well-known/openid-configuration";
      description = "URL path of the discovery document.";
    };
    jwksPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/.well-known/jwks.json";
      description = "URL path of the JSON Web Key Set.";
    };
    publicKeys = lib.mkOption {
      description = ''
        Public halves of the signing keys, published in the JWKS. Entries are
        printed by `sudo oidc-issuer-keygen` on reaper. Keep a retired key
        listed until the tokens it signed have expired.
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            kid = lib.mkOption {
              type = lib.types.str;
              description = "Key ID: the RFC 7638 thumbprint of the key.";
            };
            x = lib.mkOption {
              type = lib.types.str;
              description = "P-256 public point x coordinate, base64url.";
            };
            y = lib.mkOption {
              type = lib.types.str;
              description = "P-256 public point y coordinate, base64url.";
            };
          };
        }
      );
    };

    discoveryDocument = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Contents of /.well-known/openid-configuration.";
      # the fields AWS requires of a provider
      # (https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
      default = {
        issuer = cfg.url;
        jwks_uri = "${cfg.url}${cfg.jwksPath}";
        response_types_supported = [ "id_token" ];
        subject_types_supported = [ "public" ];
        id_token_signing_alg_values_supported = [ algorithm ];
        claims_supported = [
          "iss"
          "sub"
          "aud"
          "iat"
          "exp"
          "jti"
        ];
      };
    };
    jwks = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Contents of the JSON Web Key Set.";
      default.keys = map (key: {
        inherit (key) kid x y;
        kty = "EC";
        crv = "P-256";
        alg = algorithm;
        use = "sig";
      }) cfg.publicKeys;
    };
  };

  config = {
    # Paste entries printed by `sudo oidc-issuer-keygen` on reaper here.
    my.oidcIssuer.publicKeys = [ ];

    assertions = [
      {
        assertion = lib.allUnique (map (key: key.kid) cfg.publicKeys);
        message = "my.oidcIssuer.publicKeys: every kid must be unique.";
      }
    ];
  };
}
