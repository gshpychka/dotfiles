{
  lib,
  stdenv,
  fetchFromGitHub,
  swift,
  apple-sdk_14,
  sqlite,
  darwinMinVersionHook,
}:

# Upstream builds with XcodeGen + xcodebuild, neither of which runs in the Nix
# sandbox, so the three modules (GRDB, DataMeterCore, the app) are compiled with
# swiftc directly and the .app bundle is assembled by hand.
let
  # Upstream pins GRDB 7.x, which needs Swift 6. nixpkgs ships Swift 5.10, so this
  # uses the last GRDB release that supports Swift 5. DataMeterCore only touches
  # DatabaseQueue, DatabaseMigrator, Configuration and Row.fetchAll, which are
  # source-compatible across both majors.
  grdb = fetchFromGitHub {
    owner = "groue";
    repo = "GRDB.swift";
    tag = "v6.29.3";
    hash = "sha256-4KBAZv4cb+sgs6jvP2zj7chC5qRCirK/Y8rFLfsh+Bk=";
  };
in
stdenv.mkDerivation {
  pname = "datameter";
  version = "0-unstable-2026-05-30";

  src = fetchFromGitHub {
    owner = "emmanuelchucks";
    repo = "DataMeter";
    rev = "ced02b88f53cd7bbdde7076c5b5e818e96a2eed4";
    hash = "sha256-GcLq2TvW1U9MmCNmBpDJRhbk33SwDSC6pTguB6XY4Bg=";
  };

  nativeBuildInputs = [ swift ];
  buildInputs = [
    apple-sdk_14
    sqlite
    # SwiftUI Table, MenuBarExtra and SMAppService need macOS 13+; upstream
    # targets 14.0
    (darwinMinVersionHook "14.0")
  ];

  # openSettings and appearsActive are declared in the macOS 15 SDK (back-deployed
  # to 14), which needs Swift 6. These swap in the macOS 14 SDK equivalents.
  postPatch = ''
    substituteInPlace DataMeterApp/Features/MenuBar/MenuBarRootView.swift \
      --replace-fail '@Environment(\.openSettings) private var openSettings' "" \
      --replace-fail 'Button("Settings") { openSettings() }' 'SettingsLink { Text("Settings") }'

    substituteInPlace DataMeterApp/Features/Settings/SettingsView.swift \
      --replace-fail '@Environment(\.appearsActive) private var appearsActive' \
                     '@Environment(\.controlActiveState) private var controlActiveState' \
      --replace-fail '.onChange(of: appearsActive) { _, isActive in' \
                     '.onChange(of: controlActiveState) { _, state in let isActive = state != .inactive;'
  '';

  buildPhase = ''
    runHook preBuild

    mkdir build

    # nixpkgs strips sqlite3.h from the SDK, so the SDK's SQLite3 module can't
    # build. SWIFT_PACKAGE makes GRDB import its CSQLite shim module, which
    # includes <sqlite3.h> from nixpkgs sqlite. SQLITE_ENABLE_FTS5 matches
    # GRDB's Package.swift.
    csqlite="-I ${grdb}/Sources/CSQLite -Xcc -I${lib.getDev sqlite}/include"

    swiftc -O -parse-as-library -module-name GRDB \
      -D SWIFT_PACKAGE -D SQLITE_ENABLE_FTS5 $csqlite \
      -emit-module -emit-module-path build/GRDB.swiftmodule \
      -emit-library -static -o build/libGRDB.a \
      $(find ${grdb}/GRDB -name '*.swift')

    swiftc -O -parse-as-library -module-name DataMeterCore \
      -I build $csqlite \
      -emit-module -emit-module-path build/DataMeterCore.swiftmodule \
      -emit-library -static -o build/libDataMeterCore.a \
      $(find DataMeterCore -name '*.swift')

    swiftc -O -parse-as-library -module-name DataMeter \
      -I build $csqlite -L build -lDataMeterCore -lGRDB \
      -o build/DataMeter \
      $(find DataMeterApp -name '*.swift')

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app=$out/Applications/DataMeter.app/Contents
    mkdir -p $app/MacOS $app/Resources

    install -m755 build/DataMeter $app/MacOS/DataMeter
    # The asset catalog needs actool (Xcode only); upstream's post-build step
    # overwrites the catalog's icon with this .icns anyway
    cp scripts/assets/AppIcon.icns $app/Resources/AppIcon.icns

    # Fill in the build-setting placeholders xcodebuild would expand
    substitute DataMeterApp/App/Info.plist $app/Info.plist \
      --replace-fail '$(DEVELOPMENT_LANGUAGE)' en \
      --replace-fail '$(EXECUTABLE_NAME)' DataMeter \
      --replace-fail '$(PRODUCT_BUNDLE_IDENTIFIER)' com.emmanuelchucks.DataMeter \
      --replace-fail '$(PRODUCT_NAME)' DataMeter \
      --replace-fail '$(PRODUCT_BUNDLE_PACKAGE_TYPE)' APPL \
      --replace-fail '$(MACOSX_DEPLOYMENT_TARGET)' 14.0 \
      --replace-fail '</dict>' '<key>CFBundleIconFile</key><string>AppIcon</string></dict>'

    runHook postInstall
  '';

  meta = {
    description = "macOS app for tracking per-app network data usage locally";
    homepage = "https://github.com/emmanuelchucks/DataMeter";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "DataMeter";
  };
}
