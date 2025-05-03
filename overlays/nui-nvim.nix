self: super: {
  vimPlugins = super.vimPlugins // {
    nui-nvim = super.vimUtils.buildVimPlugin {
      name = "nui-nvim";
      src = super.fetchFromGitHub {
        owner = "MunifTanjim";
        repo = "nui.nvim";
        rev = "8d3bce9";
        hash = "sha256-BYTY2ezYuxsneAl/yQbwL1aQvVWKSsN3IVqzTlrBSEU=";
      };
    };
  };
}
