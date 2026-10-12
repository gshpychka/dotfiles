{ config, lib, ... }:
# Public face of the fleet's OIDC token issuers: their URLs and the documents
# a relying party (AWS STS) fetches to verify their tokens. Shared because two
# machines need the same values: the issuing machine signs tokens
# (modules/system/nixos/oidc-issuer.nix) and buoy publishes these documents
# (machines/buoy/oidc-discovery.nix), so issuing machines serve nothing
# publicly.
let
  cfg = config.my.oidcIssuer;
  # The only key type the signer generates: ECDSA P-256, which AWS accepts as ES256.
  algorithm = "ES256";
  # fixed by OIDC Discovery; AWS appends it to the issuer URL
  discoverySuffix = "/.well-known/openid-configuration";

  publicKeyType = lib.types.submodule {
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
  };

  issuerType = lib.types.submodule (
    { name, config, ... }:
    {
      options = {
        publicKeys = lib.mkOption {
          type = lib.types.listOf publicKeyType;
          default = [ ];
          description = ''
            Public halves of this issuer's signing keys, published in its
            JWKS. Entries are printed by `sudo oidc-issuer-keygen` on the
            machine. Keep a retired key listed until the tokens it signed have
            expired.
          '';
        };
        url = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "https://${cfg.host}/${name}";
          description = ''
            Issuer identifier: the `iss` claim, and the provider URL AWS is
            configured with. AWS fetches `<url>` + `/.well-known/openid-configuration`.
          '';
        };
        discoveryPath = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "/${name}${discoverySuffix}";
          description = "URL path of the discovery document.";
        };
        jwksPath = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "/${name}/.well-known/jwks.json";
          description = "URL path of the JSON Web Key Set.";
        };
        discoveryDocument = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Contents of the discovery document.";
          # the fields AWS requires of a provider
          # (https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
          default = {
            issuer = config.url;
            jwks_uri = "https://${cfg.host}${config.jwksPath}";
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
          }) config.publicKeys;
        };
      };
    }
  );
in
{
  options.my.oidcIssuer = {
    host = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      # infra/buoy/dns.tf points this name at buoy's tunnel
      default = "tokens.${config.my.domain}";
      description = "Public hostname every issuer's documents are served from.";
    };
    audience = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      # the audience GitHub Actions and the AWS docs use for STS
      default = "sts.amazonaws.com";
      description = "`aud` claim of every token; the client ID registered with each AWS OIDC provider.";
    };
    jwksCacheSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      readOnly = true;
      # AWS caches a JWKS for as long as its response allows
      default = 300;
      description = ''
        How long relying parties may cache a published JWKS. A newly
        published key is only safe to sign with once this has passed since
        the deploy that published it.
      '';
    };
    issuers = lib.mkOption {
      type = lib.types.attrsOf issuerType;
      default = { };
      description = ''
        One issuer per issuing machine, named after its hostname. Each has its
        own URL (https://<host>/<name>) and key set, and AWS gets one OIDC
        provider per issuer, so a role trusts exactly one machine and that
        machine's key can't mint tokens any other machine's roles accept.
      '';
    };
  };

  config = {
    # One entry per machine with my.oidcIssuer.enable; paste the entries
    # `sudo oidc-issuer-keygen` prints on that machine into its publicKeys.
    my.oidcIssuer.issuers = {
      reaper.publicKeys = [ ];
    };

    assertions = lib.concatLists (
      lib.mapAttrsToList (name: issuer: [
        {
          # the name is a URL path segment and part of AWS condition keys
          assertion = builtins.match "[a-z0-9-]+" name != null;
          message = "my.oidcIssuer.issuers.${name}: name it after its machine's hostname (lowercase letters, digits, dashes).";
        }
        {
          assertion = lib.allUnique (map (key: key.kid) issuer.publicKeys);
          message = "my.oidcIssuer.issuers.${name}.publicKeys: every kid must be unique.";
        }
        {
          # every published key can sign tokens AWS accepts, and an extra one
          # is easy to miss in review; rotation needs at most the old and new
          assertion = lib.length issuer.publicKeys <= 2;
          message = "my.oidcIssuer.issuers.${name}.publicKeys: at most two keys (the active one and the one it replaces).";
        }
      ]) cfg.issuers
    );
  };
}
