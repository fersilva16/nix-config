# My NixOS configuration

## Darwin installation

1. Install Nix: https://nixos.org/download/
2. `softwareupdate --install-rosetta`
3. `sudo nix run nix-darwin --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake .#m1`

Rebuild: `sudo darwin-rebuild switch --flake .#m1`
