{
  lib,
  vimUtils,
  fetchFromGitHub,
}:

vimUtils.buildVimPlugin rec {
  pname = "ts-error-translator.nvim";
  version = "2.0.1";

  src = fetchFromGitHub {
    owner = "dmmulroy";
    repo = "ts-error-translator.nvim";
    rev = "v${version}";
    sha256 = "sha256-/eLbUkjFpAneMoITdknATvpDjnA5XMUjEKaDq0CG+ys=";
  };

  meta = with lib; {
    description = "A Neovim port of Matt Pocock's ts-error-translator for VSCode for turning messy and confusing TypeScript errors into plain English";
    homepage = "https://github.com/dmmulroy/ts-error-translator.nvim";
    license = licenses.mit;
    maintainers = [ ];
  };
}
