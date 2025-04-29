self: super: {
  nzbget = super.nzbget.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ super.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/nzbget \
        --prefix PATH : ${super.lib.makeBinPath [ super.unrar super.p7zip ]}
    '';
  });
}
