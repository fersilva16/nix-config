{ lib, pkgs, stdenv, fetchurl, dpkg }:
let
  pname = "ticktick";
  version = "0.0.5";

  buildInputs = with pkgs; [
    gtk3
    stdenv.cc.cc
    zlib
    glib
    dbus
    atk
    pango
    freetype
    libgnome-keyring3
    fontconfig
    gdk-pixbuf
    cairo
    cups
    expat
    libgpg-error
    alsa-lib
    nspr
    nss
    xorg.libXrender
    xorg.libX11
    xorg.libXext
    xorg.libXdamage
    xorg.libXtst
    xorg.libXcomposite
    xorg.libXi
    xorg.libXfixes
    xorg.libXrandr
    xorg.libXcursor
    xorg.libxkbfile
    xorg.libXScrnSaver
    systemd
    libnotify
    xorg.libxcb
    at-spi2-atk
    at-spi2-core
    libdbusmenu
    libdrm
    mesa
    xorg.libxshmfence
    libxkbcommon
  ];

  libPathNative = { packages }: lib.makeLibraryPath packages;
in
stdenv.mkDerivation {
  inherit pname version buildInputs;

  src = fetchurl {
    url = "https://appest-public.s3.amazonaws.com/download/linux/linux_deb_x64/ticktick-${version}-amd64.deb";
    sha256 = "sha256-u4T8zi/6NdTAh/2wPnHNdy0dalolXWXY2YjOWv/GfM4=";
  };

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  doInstallCheck = true;

  nativeBuildInputs = [ dpkg ];

  unpackPhase = "dpkg-deb -x $src .";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    mv opt $out
    mv usr/share/applications $out
    ln -s $out/opt/TickTick/ticktick $out/bin/ticktick
    runHook postInstall
  '';

  postFixup =
    let
      libpath = libPathNative { packages = buildInputs; };
    in
    ''
      app=$out/opt/TickTick
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        --set-rpath "${libpath}:$app" \
        $app/ticktick
    '';

  meta = with lib; {
    description = "A task management app that helps users to stay organized";
    homepage = "https://ticktick.com";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
