{
  fetchurl,
  lib,
  runCommand,
  typescript,
}:
# node_modules tree for the pi extension sources: the npm tarballs carry the .d.ts
# files that pi's own closure omits, and the typescript links let tsserver and
# tsc.nvim resolve a compiler without an npm install.
let
  # pi release the extension API is typed against; bumped alongside the extensions
  version = "0.84.3";
  api = {
    pi-coding-agent = "sha256-0H3EF/eKFNrDdqh4tlVrUZYfEY95dx7jdTM9xRNWvHU=";
    pi-agent-core = "sha256-ajYct4QlGCDcnYrEhNgLxFTa1hk07DpfYPVo3eFW4x0=";
    pi-ai = "sha256-nECvL0OVD46U57vNDBs1SPAAly2gDE+5wNBSnU19VDE=";
    pi-client = "sha256-cj7lMlmSUouMoUZAeUqj/qxAupmsA0C7M4tpj1i1P9w=";
    pi-protocol = "sha256-Lkp5EPDUYvzd9r0ZbJbfsdqsQcMEiq5Vvzc6/R9iU7E=";
    pi-tui = "sha256-5TFNRrA7ZzW/oMkifAm6xU+eDfE0QJ+LhuVlCy7AKFw=";
  };
  vendored =
    lib.mapAttrsToList (name: hash: {
      dir = "@earendil-works/${name}";
      src = fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/${name}/-/${name}-${version}.tgz";
        inherit hash;
      };
    }) api
    ++ [
      {
        dir = "typebox";
        src = fetchurl {
          url = "https://registry.npmjs.org/typebox/-/typebox-1.3.7.tgz";
          hash = "sha256-sdCUJWDmSTbKnOMolJtabIJY6NCFEa3bfuu1TP2ghjo=";
        };
      }
      {
        # major matches pkgs.nodejs, the runtime pi loads extensions with
        dir = "@types/node";
        src = fetchurl {
          url = "https://registry.npmjs.org/@types/node/-/node-24.10.1.tgz";
          hash = "sha256-VUx7KFvn2S9cftMl9RMz6+4THEsNwquiLYrXGgH0w+Y=";
        };
      }
    ];
in
runCommand "pi-extension-types" { } (
  ''
    mkdir -p $out/.bin
    ln -s ${typescript}/lib/node_modules/typescript $out/typescript
    ln -s ${typescript}/bin/tsc $out/.bin/tsc
  ''
  + lib.concatMapStrings (
    { dir, src }:
    ''
      mkdir -p $out/${dir}
      tar xzf ${src} -C $out/${dir} --strip-components=1
    ''
  ) vendored
)
