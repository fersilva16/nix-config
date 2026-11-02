# noctalia-shell with its quickshell fork patched for Qt 6.12, which rejects
# MOC'd properties whose pointee type is only forward-declared ("Meta Types
# must be fully defined"). The patch is upstream quickshell 5d5d498 ("all:
# use MOC includes instead of opaque pointer definitions"), rebased onto
# noctalia-qs: the fork predates it and legacy-v4 is frozen upstream. Shared
# by ./noctalia.nix and modules/linux/niri/niri.nix so both use one build.
#
# Qt 6.12 also adds a built-in QtQuick `Color` singleton that shadows
# noctalia's qs.Commons `Color`, so every color resolves to undefined and the
# bar draws as blank boxes. It is exported as QtQuick 6.12, so pinning the
# QtQuick (and QtQuick.Window, which re-exports it) imports to 6.11 hides it.
# Same fix as the community legacy-v4 fork (noctalia commit 0099011). Plugins
# that read `Color` need it too: see ./screen-recorder.nix and the local ones.
{ inputs, system }:
(inputs.noctalia.packages.${system}.default.override (old: {
  quickshell = old.quickshell.overrideAttrs (qs: {
    patches = (qs.patches or [ ]) ++ [ ./quickshell-moc-includes.patch ];
  });
})).overrideAttrs
  (old: {
    postPatch = (old.postPatch or "") + ''
      find . -name '*.qml' -exec sed -i -E 's/^(\s*import QtQuick(\.Window)?)\s*$/\1 6.11/' {} +
    '';
  })
