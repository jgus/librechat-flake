{
  description = "LibreChat (danny-avila/LibreChat) — multi-provider chat UI.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    flake-lib = {
      url = "github:jgus/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flake-lib }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pin = import ./pin.nix;
        inherit (pin) version sourceRev sourceHash npmDepsHash;
        source = { type = "github"; owner = "danny-avila"; repo = "LibreChat"; };
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        # Forked from nixpkgs pkgs/by-name/li/librechat/package.nix (the two patches are copied verbatim). Kept deliberately close to upstream so re-syncing on a future nixpkgs bump is a diff, not a rewrite.
        librechat = pkgs.buildNpmPackage (finalAttrs: {
          pname = "librechat";
          inherit version;

          src = pkgs.fetchFromGitHub {
            owner = "danny-avila";
            repo = "LibreChat";
            rev = sourceRev;
            hash = sourceHash;
          };

          patches = [
            # buildNpmPackage uses `npm pack`, which honours package.json `files`; LibreChat doesn't set it, so add the paths we need (and a `bin` for the auto-generated wrapper).
            ./0001-npm-pack.patch
            # Uploads default to the (immutable) package dir; make them relative to cwd instead.
            ./0002-upload-paths.patch
          ];

          npmDepsFetcherVersion = 2;
          inherit npmDepsHash;

          # npm install fails on nodejs_24 (NixOS/nixpkgs#474535).
          nodejs = pkgs.nodejs_22;

          nativeBuildInputs = [ pkgs.pkg-config pkgs.node-gyp ];
          buildInputs = [ pkgs.vips ];

          npmBuildScript = "frontend";
          npmPruneFlags = [ "--production" ];

          makeWrapperArgs = [ "--set-default LIBRECHAT_LOG_DIR ./logs" ];

          # npmConfigHook patches only the root node_modules; nested workspace installs (client/, packages/*) need patching too.
          postConfigure = ''
            patchShebangs client/node_modules packages
          '';

          # The api/ and client/ workspace dist dirs vanish after the build (symlink churn); copy them back.
          preFixup = ''
            mkdir -p $out/lib/node_modules/LibreChat/packages/api
            cp -R packages/api/dist/. $out/lib/node_modules/LibreChat/packages/api
            mkdir -p $out/lib/node_modules/LibreChat/packages/client
            cp -R packages/client/dist/. $out/lib/node_modules/LibreChat/packages/client
          '';

          meta = {
            description = "Open-source app for all your AI conversations, fully customizable and compatible with any AI provider";
            homepage = "https://github.com/danny-avila/LibreChat";
            changelog = "https://www.librechat.ai/changelog/v${version}";
            license = lib.licenses.mit;
            mainProgram = "librechat-server";
          };
        });

        update-version = flake-lib.lib.mkUpdateVersion {
          inherit pkgs source;
          buildAttr = "librechat";
          extraHashes = [ "npmDepsHash" ];
          # fetcherVersion 2 must match npmDepsFetcherVersion above (it changes the hash).
          artifactHook = flake-lib.lib.mkJsDepsHook { inherit pkgs; manager = "npm"; fetcherVersion = 2; };
        };

        update-branches = flake-lib.lib.mkUpdateBranches {
          inherit pkgs source;
          pinSchema = "github-npm";
          excludePrereleases = true; # upstream tags X.Y.Z-rcN; track stable only
        };
      in
      {
        packages = {
          inherit librechat update-version update-branches;
          default = librechat;
        };
      });
}
