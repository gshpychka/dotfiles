# Ghostty identifies itself via XTVERSION as "ghostty <version>", a prefix tmux's
# terminal registry doesn't match, so Ghostty gets none of tmux's default terminal
# features. This patch adds a Ghostty entry (detection in tty-keys.c, feature set in
# tty-features.c) covering OSC 9;4 progress, synchronized output, OSC 7 and OSC 8
# hyperlinks. Carried until the entry lands upstream and reaches nixpkgs.
_final: prev: {
  tmux = prev.tmux.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./tmux-ghostty-features.patch ];
  });
}
