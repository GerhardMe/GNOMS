# Battery warning popup — the bare X11 window battery-monitor.sh throws up
# at 4 %. Built by nix so it lives in the system closure: the binary is
# linked against the same glibc/libX11/libXft as the current generation
# and has a GC root, so garbage collection can never pull its loader out
# from under it (which is what killed the old prebuilt battery_popup.run).
#
# Installed into home.packages by home.nix; the script calls `battery-popup`
# from PATH.
{ stdenv, pkg-config, libx11, libxft, libxrender, freetype, fontconfig }:

stdenv.mkDerivation {
  pname = "battery-popup";
  version = "1.0";

  src = ./.;

  nativeBuildInputs = [ pkg-config ];
  # xft.pc requires xrender, fontconfig and freetype2, so pkg-config needs
  # all of them on the search path, not just X11 and Xft.
  buildInputs = [ libx11 libxft libxrender freetype fontconfig ];

  buildPhase = ''
    runHook preBuild
    $CXX -O2 battery_popup.cpp -o battery-popup $(pkg-config --cflags --libs x11 xft)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 battery-popup "$out/bin/battery-popup"
    runHook postInstall
  '';

  meta.description = "Bare X11 low-battery warning popup for GNOMS";
}
