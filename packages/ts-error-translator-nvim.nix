{
  lib,
  vimUtils,
  fetchFromGitHub,
}:

vimUtils.buildVimPlugin {
  pname = "ts-error-translator.nvim";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "dmmulroy";
    repo = "ts-error-translator.nvim";
    rev = "v1.2.0";
    sha256 = "08whn7l75qv5n74cifmnxc0s7n7ja1g7589pjnbbsk2djn6bqbky";
  };

  meta = with lib; {
    description = "A Neovim port of Matt Pocock's ts-error-translator for VSCode for turning messy and confusing TypeScript errors into plain English";
    homepage = "https://github.com/dmmulroy/ts-error-translator.nvim";
    license = licenses.mit;
    maintainers = [ ];
  };
}