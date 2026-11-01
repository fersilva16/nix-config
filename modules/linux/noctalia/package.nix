# noctalia-shell with its quickshell fork patched for Qt 6.12, which rejects
# MOC'd properties whose pointee type is only forward-declared ("Meta Types
# must be fully defined"). The patch is upstream quickshell 5d5d498 ("all:
# use MOC includes instead of opaque pointer definitions"), rebased onto
# noctalia-qs: the fork predates it and legacy-v4 is frozen upstream. Shared
# by ./noctalia.nix and modules/linux/niri/niri.nix so both use one build.
{ inputs, system }:
inputs.noctalia.packages.${system}.default.override (old: {
  quickshell = old.quickshell.overrideAttrs (qs: {
    patches = (qs.patches or [ ]) ++ [ ./quickshell-moc-includes.patch ];
  });
})
