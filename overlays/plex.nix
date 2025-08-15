final: prev: {
  plexRaw = prev.plexRaw.overrideAttrs (oldAttrs: rec {
    # https://github.com/NixOS/nixpkgs/issues/433054
    version = "1.42.1.10060-4e8b05daf";
    src =
      if prev.stdenv.hostPlatform.system == "aarch64-linux" then
        prev.fetchurl {
          url = "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_arm64.deb";
          sha256 = "1rxhj7gf78rjp0g60k9q6jspz7pzinnnqp9x78zxrbm82xdn637i";
        }
      else
        prev.fetchurl {
          url = "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_amd64.deb";
          sha256 = "1x4ph6m519y0xj2x153b4svqqsnrvhq9n2cxjl50b9h8dny2v0is";
        };
  });
}

