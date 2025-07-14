# My NixOS configuration

## Darwin installation

1. `curl -L https://nixos.org/nix/install | sh`
2. `mkdir -p ~/.config/nix` (optional)
3. ```sh
   cat <<EOF > ~/.config/nix/nix.conf
   experimental-features = nix-command flakes
   EOF
   ```
4. `nix run nix-darwin -- switch --flake .`

Rebuild: `sudo darwin-rebuild switch --flake .#m1`
