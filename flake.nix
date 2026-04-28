{
  description = "A Nix-flake-based Java development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      javaVersion = 25;
      pname = "matsim-example-project";
      version = "0.0.1-SNAPSHOT";
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            };
          in
          f { inherit pkgs system; }
        );

      mkJavaEnv =
        {
          pkgs,
          system,
        }:
        pkgs.mkShellNoCC {
          packages = with pkgs; [
            gcc
            gradle
            jdk
            maven
            ncurses
            patchelf
            zlib
            self.formatter.${system}
          ];

          shellHook =
            let
              loadLombok = "-javaagent:${pkgs.lombok}/share/java/lombok.jar";
              prev = "\${JAVA_TOOL_OPTIONS:+ $JAVA_TOOL_OPTIONS}";
            in
            ''
              export JAVA_TOOL_OPTIONS="${loadLombok}${prev}"
            '';
        };

      mkMatsimPackage =
        { pkgs, ... }:
        pkgs.maven.buildMavenPackage {
          inherit pname version;
          src = pkgs.lib.cleanSource ./.;
          mvnHash = "sha256-ZT76jG1oFR3i1xF7Ej0R757Osh+pIdk2xG3JcMlkqsQ=";
          mvnParameters = "-DskipTests";

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin $out/share/${pname}
            install -Dm644 ${pname}-${version}.jar $out/share/${pname}/${pname}.jar

            makeWrapper ${pkgs.jdk}/bin/java $out/bin/${pname} \
              --add-flags "-jar $out/share/${pname}/${pname}.jar"

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "MATSim example project packaged as a Nix flake app";
            mainProgram = pname;
            license = licenses.gpl2Only;
            platforms = supportedSystems;
          };
        };
    in
    {
      overlays.default =
        final: prev:
        let
          jdk = prev."jdk${toString javaVersion}";
        in
        {
          inherit jdk;
          maven = prev.maven.override { jdk_headless = jdk; };
          gradle = prev.gradle.override { java = jdk; };
          lombok = prev.lombok.override { inherit jdk; };
        };

      packages = forEachSupportedSystem (
        { pkgs, system }:
        let
          matsimPackage = mkMatsimPackage { inherit pkgs system; };
        in
        {
          default = matsimPackage;
          ${pname} = matsimPackage;
        }
      );

      apps = forEachSupportedSystem (
        { system, ... }:
        {
          default = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/${pname}";
            meta.description = "Run the MATSim example application";
          };

          ${pname} = self.apps.${system}.default;
        }
      );

      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = mkJavaEnv { inherit pkgs system; };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);
    };
}
