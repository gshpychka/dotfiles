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
      (self: super: {
        ctranslate2 = super.ctranslate2.override {
          withCUDA = true;
          withCuDNN = true;
        };
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
