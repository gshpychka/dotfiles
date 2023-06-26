self: super:
let
  treeSitterWing = self.stdenv.mkDerivation {
    pname = "tree-sitter-wing";
    version = "0.0.0";

    src = self.fetchFromGitHub {
      owner = "winglang";
      repo = "win";
      rev = "cb25f3ecc4f663c1d82af400ff1a714dc7354018";
      sha256 = "";
    };

    configurePhase = ''
      cd libs/tree-sitter-wing 
      tree-sitter generate
    '';

    buildInputs = [ self.tree-sitter self.nodejs ];
    buildPhase = ''
      runHook preBuild
      if [[ -e src/scanner.cc ]]; then
      $CXX -fPIC -c src/scanner.cc -o scanner.o $CXXFLAGS
      elif [[ -e src/scanner.c ]]; then
      $CC -fPIC -c src/scanner.c -o scanner.o $CFLAGS
      fi
      $CC -fPIC -c src/parser.c -o parser.o $CFLAGS
      rm -rf parser
      $CXX -shared -o parser *.o
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir $out
      mv parser $out/
      if [[ -d queries ]]; then
        cp -r queries $out
      fi
      runHook postInstall
    '';

  };
in
{
  tree-sitter = super.tree-sitter.overrideAttrs (oldAttrs: {
    extraGrammars = oldAttrs.extraGrammars // {
      tree-sitter-wing = treeSitterWing;
    };
  });
}

