{
  mkUserModule,
  pkgs,
  ...
}:
let
  configDir = "Library/Application Support/Code/User";

  # Full VS Code Marketplace exposed as Nix packages via the
  # nix-vscode-extensions overlay (wired in lib/mkDarwinHost.nix).
  marketplace = pkgs.vscode-marketplace;
in
mkUserModule {
  name = "vscode";

  # The editor itself comes from nixpkgs (via programs.vscode below) so that
  # extensions can be managed declaratively — there is no Homebrew cask.
  home =
    _:
    # Nested function so we get home-manager's `config` (needed for
    # mkOutOfStoreSymlink), which mkUserModule's home builder doesn't pass.
    { config, ... }:
    {
      programs.vscode = {
        enable = true;
        package = pkgs.vscode;

        # Keep the extensions dir writable so extensions declared here coexist
        # with ones installed manually from the Marketplace later.
        mutableExtensionsDir = true;

        profiles.default.extensions = with marketplace; [
          # Formatters / linters
          oxc.oxc-vscode
          esbenp.prettier-vscode
          dbaeumer.vscode-eslint
          redhat.vscode-yaml
          redhat.vscode-xml
          golang.go
          # Languages
          jnoortheen.nix-ide
          elixir-lsp.elixir-ls
          # Tooling
          mkhl.direnv
          eamodio.gitlens
          arturock.gitstash
          ms-vscode-remote.remote-ssh
          # AI completion
          supermaven.supermaven
          # Theme
          raillyhugo.one-hunter
        ];
      };

      # Settings are nix-first but live-writable: this points VS Code's
      # settings.json at the repo file via an out-of-store symlink, so edits in
      # the UI write straight back to the repo (and survive rebuilds). Assumes
      # the flake lives at ~/nix-config.
      home.file."${configDir}/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/modules/editor/vscode/settings.json";
    };
}
