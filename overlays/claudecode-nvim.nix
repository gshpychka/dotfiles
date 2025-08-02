final: prev: {
  vimPlugins = prev.vimPlugins // {
    claudecode-nvim = prev.vimPlugins.claudecode-nvim.overrideAttrs (oldAttrs: {
      version = "2025-07-30";
      src = final.fetchFromGitHub {
        owner = "coder";
        repo = "claudecode.nvim";
        rev = "d0f97489d9064bdd55592106e99aa5f355a09914";
        sha256 = "1x5lp5s1par0zqasnldz46gc8jdv5h63adr6b105ql3xja6lyrma";
      };
    });
  };
}