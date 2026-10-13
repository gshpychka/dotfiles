# A GitHub App as the agent's GitHub identity: git and gh in its commands
# authenticate as the App and commit as <slug>[bot].
#
# Imperative, one-time, signed in to github.com as the owner:
#   1. Settings > Developer settings > GitHub Apps > New GitHub App: any
#      homepage URL, webhook off, "Only on this account"; repository
#      permissions Contents, Pull requests and Workflows read and write.
#      Note the App ID and the slug.
#   2. Generate a private key; in a checkout of this repository, store it
#      and delete the download:
#        jq -Rs . < key.pem | sops set --value-stdin <sopsFile> '["github-app-private-key"]'
#        rm key.pem
#   3. Install App > the owner's account > only select repositories. The
#      installation ID ends the installation's settings URL.
#   4. The bot user's ID:
#        curl -s 'https://api.github.com/users/<slug>%5Bbot%5D' | jq .id
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  app = cfg.github;
  gw = config.services.openclaw-gateway;
  secretName = "openclaw/github-app-private-key";

  # Prints an installation token of the App.
  mintToken = pkgs.writeShellApplication {
    name = "openclaw-github-token";
    text = ''
      # base64url (--base64url) on one line (-w0), its padding removed (tr -d '='): a JWT's encoding of each part
      b64url() { ${lib.getExe' pkgs.coreutils "basenc"} --base64url -w0 | ${lib.getExe' pkgs.coreutils "tr"} -d '='; }
      # the current time as seconds since 1970 (+%s)
      now=$(${lib.getExe' pkgs.coreutils "date"} +%s)
      # the JWT's header: an RS256 signature
      header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
      # the JWT's claims: the App, issued a minute back for clock drift, expiring in 9 minutes within GitHub's 10
      payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" ${toString app.appId} | b64url)
      # the JWT's signature: header.payload hashed with SHA-256 and signed (-sign) with the App's key, as raw bytes (-binary)
      signature=$(printf '%s.%s' "$header" "$payload" | ${lib.getExe pkgs.openssl} dgst -sha256 -sign ${
        config.sops.secrets.${secretName}.path
      } -binary | b64url)
      # the JWT as a request header, written to the pipe: process arguments are world-readable
      printf 'Authorization: Bearer %s.%s.%s\n' "$header" "$payload" "$signature" |
        # a POST (-X) exchanging it for an installation token, headers read from the pipe (-H @-), quiet but for errors (-sS), failing on an HTTP error (-f)
        ${lib.getExe pkgs.curl} -fsS -X POST -H @- -H 'Accept: application/vnd.github+json' https://api.github.com/app/installations/${toString app.installationId}/access_tokens |
        # the response's token as plain text (-r), failing when it has none (-e)
        ${lib.getExe pkgs.jq} -er .token
    '';
  };

  # a git credential helper (https://git-scm.com/docs/gitcredentials#_custom_helpers)
  credentialHelper = pkgs.writeShellScript "openclaw-github-git-credential" ''
    # whether git asks for credentials (get), the one request of the protocol that needs an answer
    if [ "$1" = get ]; then
      # the user name GitHub takes with an App token, and a fresh token as the password
      printf 'username=x-access-token\npassword=%s\n' "$(${lib.getExe mintToken})"
    fi
  '';

  # gh, signed in as the App
  gh = pkgs.writeShellApplication {
    name = "gh";
    text = ''
      # a fresh installation token, in the variable gh signs in with
      GH_TOKEN=$(${lib.getExe mintToken})
      # the variable handed on to gh
      export GH_TOKEN
      # gh itself in place of this shell (exec), the arguments passed on
      exec ${lib.getExe pkgs.gh} "$@"
    '';
  };

  botName = "${app.slug}[bot]";
  gitConfig = pkgs.writeText "openclaw-gitconfig" (
    lib.generators.toGitINI {
      user = {
        name = botName;
        email = "${toString app.botUserId}+${botName}@users.noreply.github.com";
      };
      credential."https://github.com".helper = "${credentialHelper}";
      # the App authenticates over HTTPS only
      url."https://github.com/".insteadOf = [
        "git@github.com:"
        "ssh://git@github.com/"
      ];
    }
  );
in
{
  options.my.openclaw.github = lib.mkOption {
    default = null;
    description = "The agent's GitHub App; null leaves the agent without GitHub credentials.";
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          appId = lib.mkOption {
            type = lib.types.ints.positive;
            description = "The App's ID.";
          };
          slug = lib.mkOption {
            type = lib.types.str;
            description = "The App's URL name, as in github.com/apps/<slug>.";
          };
          installationId = lib.mkOption {
            type = lib.types.ints.positive;
            description = "The ID of the App's installation on the owner's account.";
          };
          botUserId = lib.mkOption {
            type = lib.types.ints.positive;
            description = "The GitHub user ID of <slug>[bot], the account the agent's commits link to.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.enable && app != null) {
    sops.secrets.${secretName} = {
      inherit (cfg) sopsFile;
      key = "github-app-private-key";
      # the gateway user's git and gh sign with it
      owner = gw.user;
    };

    systemd.tmpfiles.rules = [
      "L+ ${config.users.users.${gw.user}.home}/.gitconfig - - - - ${gitConfig}"
    ];

    my.openclaw = {
      extraPackages = [
        pkgs.git
        gh
      ];
      skills.github-app = {
        description = "Clone, pull, commit and push to the owner's GitHub repositories, and open pull requests, as ${botName}.";
        text = ''
          `git` and `gh` act as the GitHub App ${botName}, over HTTPS, with no
          setup. The App writes to the repositories it is installed on and reads
          those and every public one; any other answers 404.

          Open pull requests with `gh pr create`.
        '';
      };
    };
  };
}
