final: prev: {
  uptime-kuma = prev.uptime-kuma.overrideAttrs (
    finalAttrs: prevAttrs: {
      version = "2.0.2";

      src = prevAttrs.src.override {
        rev = finalAttrs.version;
        hash = "sha256-zW5sl1g96PvDK3S6XhJ6F369/NSnvU9uSQORCQugfvs=";
      };

      npmDepsHash = "sha256-EmSZJUbtD4FW7Rzdpue6/bV8oZt7RUL11tFBXGJQthg=";

      npmDeps = prev.fetchNpmDeps {
        inherit (finalAttrs) src;
        name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
        hash = finalAttrs.npmDepsHash;
      };

      patches = [ ];
    }
  );
}
