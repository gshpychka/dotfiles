# Ghostty identifies itself via XTVERSION as "ghostty <version>", a prefix tmux's
# terminal registry doesn't match, so Ghostty gets none of tmux's default terminal
# features. This patch adds a Ghostty entry (detection in tty-keys.c, feature set in
# tty-features.c) matching tmux master. Releases through 3.7c lack the entry.
_final: prev: {
  tmux = prev.tmux.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./tmux-ghostty-features.patch ];
  });
}
