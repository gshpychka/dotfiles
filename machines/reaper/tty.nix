# Replace tty1's login prompt with a unimatrix animation.
#
# Press `q` (or Ctrl-C) on the console to exit the animation and get a normal
# login prompt. After logout the unit restarts (Restart=always is inherited
# from upstream getty@.service), so the animation resumes.
#
# Only tty1 is touched -- tty2..tty6 still spawn vanilla gettys, so
# Ctrl-Alt-F2 is always a clean escape hatch. SSH is unaffected.
{ pkgs, ... }:
let
  # agetty flags here mirror the ones NixOS's own getty wrapper passes
  # (see /etc/systemd/system/getty@.service.d/overrides.conf at runtime).
  # We duplicate the minimal set rather than re-invoking the internal NixOS
  # script, which isn't exposed as a public attribute.
  matrixGetty = pkgs.writeShellScript "matrix-getty" ''
    # `-a` async scroll, `-f` flashers, `-o` hide status line.
    # PYTHONWARNINGS=ignore suppresses unimatrix's import-time SyntaxWarnings:
    # its source has unescaped `\;` in regular string literals, which Python
    # 3.12+ flags. Without this they end up on the underlying tty.
    # `|| true`: any non-zero exit still falls through to the login prompt.
    PYTHONWARNINGS=ignore ${pkgs.unimatrix}/bin/unimatrix -a -f -o || true
    exec ${pkgs.util-linux}/bin/agetty \
      --login-program ${pkgs.shadow}/bin/login \
      --noclear --keep-baud tty1 115200,38400,9600 linux
  '';
in
{
  # tty1 runs as `autovt@tty1.service` (a `getty@` instance), so an explicit
  # `getty@tty1.service` file is ignored; the override has to be a drop-in.
  systemd.services."getty@tty1" = {
    overrideStrategy = "asDropin";
    restartIfChanged = false; # don't restart the animation on rebuild
    serviceConfig.ExecStart = [
      "" # reset inherited ExecStart list
      "${matrixGetty}"
    ];
  };

  environment.systemPackages = [ pkgs.unimatrix ];
}
