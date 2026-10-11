# A GitHub App as the agent's GitHub identity, <slug>[bot], for the main
# session's host commands and its Claude Code sessions. The App reaches only
# the repositories it is installed on, and each token it mints expires within
# the hour.
#
# Imperative, one-time, on github.com signed in as the owner:
#   1. Settings > Developer settings > GitHub Apps > New GitHub App: any
#      homepage URL, webhook off, "Only on this account"; repository
#      permissions Contents, Pull requests and Workflows read and write.
#      Note the App ID and the slug in the App's public link.
#   2. Generate a private key, then store it and delete the download:
#        jq -Rs . < key.pem | sops set --value-stdin secrets/hoard/openclaw.yaml '["github-app-private-key"]'
#   3. Install App > the owner's account > only select repositories. The
#      installation ID ends the installation's settings URL.
#   4. Bot user ID, for commit attribution:
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
  keyPath = config.sops.secrets."openclaw/github-app-private-key".path;

  # Prints an installation token, exchanged at GitHub for a JWT signed with the
  # App's key. The JWT goes to curl on stdin: process arguments are
  # world-readable.
  token = pkgs.writeShellApplication {
    name = "openclaw-github-token";
    runtimeInputs = with pkgs; [
      coreutils
      openssl
      curl
      jq
    ];
    text = ''
      b64url() { basenc --base64url -w0 | tr -d '='; }
      now=$(date +%s)
      header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
      payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" ${toString app.appId} | b64url)
      signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign ${keyPath} -binary | b64url)
      printf 'Authorization: Bearer %s.%s.%s\n' "$header" "$payload" "$signature" \
        | curl -fsS -X POST -H @- -H 'Accept: application/vnd.github+json' \
            https://api.github.com/app/installations/${toString app.installationId}/access_tokens \
        | jq -er .token
    '';
  };

  # git credential helper protocol: git only asks it for https://github.com
  credentialHelper = pkgs.writeShellScript "openclaw-github-git-credential" ''
    [ "''${1-}" = get ] || exit 0
    printf 'username=x-access-token\npassword=%s\n' "$(${lib.getExe token})"
  '';

  gh = pkgs.writeShellApplication {
    name = "gh";
    text = ''
      GH_TOKEN=$(${lib.getExe token})
      export GH_TOKEN
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
      # the empty helper drops any inherited one
      credential."https://github.com".helper = [
        ""
        "${credentialHelper}"
      ];
      # the App authenticates over HTTPS only
      url."https://github.com/".insteadOf = "git@github.com:";
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
            description = "The App ID from the App's settings page.";
          };
          slug = lib.mkOption {
            type = lib.types.str;
            description = "The App's URL name, as in github.com/apps/<slug>.";
          };
          installationId = lib.mkOption {
            type = lib.types.ints.positive;
            description = "ID of the App's installation on the owner's account.";
          };
          botUserId = lib.mkOption {
            type = lib.types.ints.positive;
            description = "User ID of <slug>[bot], which commit emails need for attribution.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.enable && app != null) {
    sops.secrets."openclaw/github-app-private-key" = {
      inherit (cfg) sopsFile;
      key = "github-app-private-key";
      owner = gw.user;
    };

    systemd.tmpfiles.rules = [ "L+ ${gw.stateDir}/.gitconfig - - - - ${gitConfig}" ];

    my.openclaw = {
      hostTools = [
        token
        gh
      ];
      skills.github = {
        description = "Clone, pull, commit and push to the owner's GitHub repositories, and open pull requests, as ${botName}.";
        text = ''
          git and `gh` act as the GitHub App ${botName}, over HTTPS, with no
          setup: credentials come from a helper. The App reaches only the
          repositories it is installed on; anything else answers 404.

          Open pull requests with `gh pr create`.
        '';
      };
    };
  };
}
