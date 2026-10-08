{
  lib,
  stdenv,
  fetchFromGitHub,
  swift,
  apple-sdk_14,
  sqlite,
  darwinMinVersionHook,
}:

# Upstream builds with XcodeGen + xcodebuild, which require Xcode.
let
  # Upstream's MACOSX_DEPLOYMENT_TARGET
  deploymentTarget = "14.0";

  # 6.29.3 is the last GRDB release that builds with nixpkgs' Swift 5.10; upstream
  # pins 7.x, which requires Swift 6. DataMeterCore's GRDB surface (DatabaseQueue,
  # DatabaseMigrator, Configuration, Row.fetchAll) is source-compatible across both.
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
    (darwinMinVersionHook deploymentTarget)
  ];

  # openSettings and appearsActive are declared in the macOS 15 SDK, which requires
  # Swift 6. SettingsLink and controlActiveState are their macOS 14 SDK equivalents.
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

    # nixpkgs' apple-sdk omits sqlite3.h; GRDB's CSQLite shim module includes it
    # from nixpkgs sqlite
    csqlite="-I ${grdb}/Sources/CSQLite -Xcc -I${lib.getDev sqlite}/include"

    # SWIFT_PACKAGE: GRDB imports the CSQLite shim module
    # SQLITE_ENABLE_FTS5: matches GRDB's Package.swift
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
    # Upstream's post-build step installs this .icns as the app icon; the asset
    # catalog requires Xcode's actool
    cp scripts/assets/AppIcon.icns $app/Resources/AppIcon.icns

    # xcodebuild expands these build-setting placeholders and actool adds
    # CFBundleIconFile
    substitute DataMeterApp/App/Info.plist $app/Info.plist \
      --replace-fail '$(DEVELOPMENT_LANGUAGE)' en \
      --replace-fail '$(EXECUTABLE_NAME)' DataMeter \
      --replace-fail '$(PRODUCT_BUNDLE_IDENTIFIER)' com.emmanuelchucks.DataMeter \
      --replace-fail '$(PRODUCT_NAME)' DataMeter \
      --replace-fail '$(PRODUCT_BUNDLE_PACKAGE_TYPE)' APPL \
      --replace-fail '$(MACOSX_DEPLOYMENT_TARGET)' ${deploymentTarget} \
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
