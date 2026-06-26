{
  description = "zerkal — floating Wayland overlay with orbiting album covers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # quickshell-git lives in its own flake; pin it so contributors get the
    # same Qt6 build the rest of the project was tested against.
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, quickshell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        qs   = quickshell.packages.${system}.default;

        # Runtime deps every entrypoint needs in PATH.
        runtimeDeps = [
          qs                  # quickshell binary
          pkgs.playerctl      # bubble-click → playerctl --player=spotify open URI
          pkgs.bash
        ];

        # The package: copies qml/ + center.png + zerkal.sh into the store,
        # then wraps the script so it can find quickshell + playerctl without
        # leaning on the user's PATH. The script auto-resolves its own QML
        # files via $(dirname "$0"), so the layout just works after install.
        zerkal = pkgs.stdenv.mkDerivation {
          pname   = "zerkal";
          version = "0.1.0";
          src     = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/share/zerkal/qml $out/bin
            cp -r qml/* $out/share/zerkal/qml/
            # Replace the script's "$(dirname "$0")"-based QML lookup with
            # the absolute store path, then wrap to inject runtime deps.
            install -m755 zerkal.sh $out/share/zerkal/zerkal.sh
            substituteInPlace $out/share/zerkal/zerkal.sh \
              --replace 'ROOT="$(cd "$(dirname "$0")" && pwd)"' \
                        'ROOT="'"$out"'/share/zerkal"'
            makeWrapper $out/share/zerkal/zerkal.sh $out/bin/zerkal \
              --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}
          '';

          meta = with pkgs.lib; {
            description = "Floating Wayland overlay with orbiting album covers";
            homepage    = "https://github.com/zerkal-beta/zerkal";
            license     = licenses.mit;
            platforms   = platforms.linux;
            mainProgram = "zerkal";
          };
        };
      in {
        packages.default = zerkal;
        packages.zerkal  = zerkal;

        # `nix run github:zerkal-beta/zerkal`        → toggle the orbital
        # `nix run github:zerkal-beta/zerkal#galaxy` → galaxy carousel
        apps.default = {
          type    = "app";
          program = "${zerkal}/bin/zerkal";
          meta    = zerkal.meta;
        };
        apps.galaxy = {
          type    = "app";
          program = "${pkgs.writeShellScript "zerkal-galaxy" ''
            exec ${zerkal}/bin/zerkal galaxy "$@"
          ''}";
        };

        # `nix develop` for hacking on the QML / shell script — same runtime
        # bins plus ImageMagick (for re-baking center.png) and watchexec
        # (hot-reload quickshell on file save).
        devShells.default = pkgs.mkShell {
          packages = runtimeDeps ++ [
            pkgs.imagemagick
            pkgs.watchexec
          ];

          shellHook = ''
            echo "zerkal dev shell ready."
            echo "  bash ./zerkal.sh toggle    — try it"
            echo "  watchexec -e qml -r 'pkill -f zerkal/qml/shell.qml; quickshell -p qml/shell.qml &' \\"
            echo "                              — hot-reload QML on save"
          '';
        };
      });
}
