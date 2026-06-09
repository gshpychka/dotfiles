# The upstream Makefile links the PAM module with raw `ld`, which doesn't pull
# in libgcc; on aarch64 the module then fails to dlopen with
# `undefined symbol: __multf3` (https://github.com/NixOS/nixpkgs/issues/386392).
# Linking through the compiler driver instead pulls in libgcc.
# Scoped to aarch64 so the x86_64 build keeps hitting the binary cache.
final: prev:
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isAarch64 {
  pam_ssh_agent_auth = prev.pam_ssh_agent_auth.overrideAttrs (old: {
    makeFlags = (old.makeFlags or [ ]) ++ [ "LD=$(CC)" ];
  });
}
