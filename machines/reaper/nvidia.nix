{
  config,
  ...
}:
{
  # Community CUDA cache: https://wiki.nixos.org/wiki/CUDA
  nix.settings = {
    extra-substituters = [ "https://cache.nixos-cuda.org" ];
    extra-trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };
  nixpkgs = {
    config = {
      # cudaSupport = true would enable CUDA for every package that has it,
      # and we don't need it on for all packages that we use
      # Omitting it does not prevent CUDA support; use per-package overrides

      # Keeping this here as a reference
      # cudaSupport = true; (do NOT uncomment)

      # Setting cudaCapabilities would change CUDA derivation hashes and
      # miss the cache
      # cudaCapabilities = [ "8.9" ]; (do NOT uncomment)

      nvidia.acceptLicense = true;
    };
    overlays = [
      # Since we don't set cudaSupport = true globally, we need to enable CUDA
      # for each package that requires it
      (_self: super: {
        ctranslate2 =
          (super.ctranslate2.override {
            withCUDA = true;
            withCuDNN = true;
          }).overrideAttrs
            (old: {
              cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                # ct2 uses CMake's legacy FindCUDA, which reads the GPU arch only
                # from CUDA_NVCC_FLAGS. nixpkgs stopped setting it, so nvcc falls
                # back to sm_52 and the fp16 kernels fail.
                # See https://github.com/NixOS/nixpkgs/pull/536525
                (super.lib.cmakeFeature "CUDA_NVCC_FLAGS" (
                  super.lib.concatStringsSep ";" super.cudaPackages.flags.gencode
                ))
              ];
            });
        btop = super.btop.override { cudaSupport = true; };
      })
    ];
  };
  hardware = {
    nvidia = {
      # ensure GPU is awake while headless
      nvidiaPersistenced = true;
      powerManagement.enable = true;
      open = true;

      # GUI settings
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.beta;
    };
    nvidia-container-toolkit.enable = true;
  };
  services.xserver = {
    videoDrivers = [ "nvidia" ];
  };
}
