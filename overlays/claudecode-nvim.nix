final: prev: {
  vimPlugins = prev.vimPlugins // {
    claudecode-nvim = prev.vimPlugins.claudecode-nvim.overrideAttrs (oldAttrs: {
      version = "2025-08-08";
      src = final.fetchFromGitHub {
        owner = "coder";
        repo = "claudecode.nvim";
        rev = "985b4b117ea13ec85c92830ecac8f63543dd5ead";
        sha256 = "";
      };
    });
  };
}
