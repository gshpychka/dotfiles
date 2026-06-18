# tmux parses escape sequences itself and silently drops any OSC it doesn't
# recognise, so Ghostty's progress-bar protocol (OSC 9 ; 4, the ConEmu
# convention) never reaches the host terminal from inside tmux.
#
# This patch adds an OSC 9 handler that forwards OSC 9 ; 4 verbatim to the
# outer terminal (only while the reporting pane is visible) instead of
# discarding it; other OSC 9 uses are ignored as before. No tmux option is
# needed - it's unconditional, since tmux has no progress state of its own.
#
# Carried as an overlay until/unless tmux gains native OSC 9 ; 4 forwarding.
_final: prev: {
  tmux = prev.tmux.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./tmux-osc9-progress.patch ];
  });
}
