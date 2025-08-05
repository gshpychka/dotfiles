final: prev: {
  vimPlugins = prev.vimPlugins // {
    claudecode-nvim = prev.vimPlugins.claudecode-nvim.overrideAttrs (oldAttrs: {
      version = "2025-07-30";
      src = final.fetchFromGitHub {
        owner = "coder";
        repo = "claudecode.nvim";
        rev = "477009003cbec7e6088dbbeab46aba80f461d5f0";
        sha256 = "P2FELIY8roeII4kVgk5BEHWkhelJCsaV6PyMIkEpC8I=";
      };
    });
  };
}
