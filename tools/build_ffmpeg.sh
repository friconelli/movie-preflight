#!/bin/zsh
# Compila ffmpeg 9.0.2 come quello di Homebrew ma con libzimg (filtro zscale: conversione HDR→SDR di qualità). Risultato in vendor/ffmpeg-zimg/bin.
# Serve: brew install pkgconf x264 x265 dav1d svt-av1 libvmaf zimg
export PKG_CONFIG_PATH=/opt/homebrew/opt/x265/lib/pkgconfig:$PKG_CONFIG_PATH
set -e; ROOT=$(cd "$(dirname "$0")/.." && pwd); mkdir -p "$ROOT/vendor"; cd "$ROOT/vendor"
[ -d ffmpeg-9.0.2 ] || { curl -sL -O https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz && tar xf ffmpeg-9.0.2.tar.xz; }
cd ffmpeg-9.0.2
P="$ROOT/vendor/ffmpeg-zimg"
./configure --prefix="$P" --enable-gpl --enable-version3 --enable-libdav1d --enable-libsvtav1 --enable-libvmaf --enable-libx264 --enable-libx265 --enable-libzimg --enable-videotoolbox --disable-ffplay --disable-doc --disable-debug
make -j$(sysctl -n hw.ncpu)
make install
echo BUILD_OK
