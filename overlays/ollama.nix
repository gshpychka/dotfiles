# https://github.com/NixOS/nixpkgs/issues/545286
_final: prev: {
  ollama-cuda = prev.ollama-cuda.overrideAttrs (old: {
    preBuild = ''
      unset CUDAToolkit_ROOT
    ''
    + old.preBuild;
  });
}
