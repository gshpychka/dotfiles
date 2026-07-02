{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

# AdGuard-format rule list
stdenvNoCC.mkDerivation {
  pname = "adguard-rules";
  # rolling upstream with no releases; nix-update --version=branch tracks main
  version = "0-unstable-2026-07-02";

  src = fetchFromGitHub {
    owner = "magicsword-io";
    repo = "LOLRMM";
    rev = "46c90fca9da5ff823b053d747abc25a9d815d97e";
    hash = "sha256-5+VP6keGs8vMnVO8KDVtIBjtrwJcKXSdTv+lviEXjBc=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    # LOLRMM domains CSV (URI column) -> AdGuard rules. ||domain^ already covers
    # subdomains, so the redundant "*." prefix is stripped; bare IP entries are
    # dropped since ||...^ only matches domain names. The output is the rule file
    # itself, so consumers reference the package's store path directly.
    tail -n +2 website/public/api/rmm_domains.csv \
      | tr -d '\r' \
      | cut -d, -f1 \
      | sed 's/^\*\.//' \
      | grep -E '[A-Za-z]' \
      | sort -u \
      | sed 's#.*#||&^#' > "$out"
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = {
    description = "AdGuard blocking rules";
    platforms = lib.platforms.all;
  };
}
