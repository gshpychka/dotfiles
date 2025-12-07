# btop 1.4.5 has a bug that breaks btrfs disk detection
# https://github.com/aristocratos/btop/issues/1270
# it's been fixed since, but not released yet
# TODO: remove overlay when btop >= 1.4.6 is released
final: prev: {
  btop = prev.btop.overrideAttrs (oldAttrs: {
    src = prev.fetchFromGitHub {
      owner = "aristocratos";
      repo = "btop";
      rev = "871c1db49f4c7ad5fce6b8af1b25422a73f74139";
      hash = "sha256-dMHN46REeS8zExYNp6YKIP1Vv8XryteC1WPQk6TD1b8=";
    };
  });
}
