{
  config,
  ...
}:
{
  nixpkgs = {
    config = {
      # We shouldn't set cudaSupport = true here, because it will lead to
      # building e.g. pytorch from source
      # Omitting it does NOT prevent CUDA support
      # If a package requires this flag, use an override

      # Keeping this here as a reference
      # cudaSupport = true; (do NOT uncomment)

      # https://en.wikipedia.org/wiki/CUDA#GPUs_supported
      cudaCapabilities = [ "8.9" ];
      cudaForwardCompat = true;
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
