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
      # cudaSupport = true would enable CUDA for every package that has it and
      # build them from source: cache.nixos-cuda.org covers channel heads, not
      # this machine's unstable pin. CUDA is enabled per package instead.
      # cudaSupport = true; (do NOT uncomment)

      # Narrowing cudaCapabilities to this GPU (8.9) changes CUDA derivation
      # hashes. Here it only rebuilds btop; the cache-sensitive default lives
      # with the whisper closure (whisper.nix).
      # cudaCapabilities = [ "8.9" ]; (do NOT uncomment)

      nvidia.acceptLicense = true;
    };
    overlays = [
      (_self: super: {
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
