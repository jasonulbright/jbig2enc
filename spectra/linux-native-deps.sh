# Builds the pinned native imaging stack: zlib, libpng, libjpeg-turbo, libtiff
# (JBIG disabled) and Leptonica, from SHA-256-verified release sources, into
# $NATIVE_PREFIX. Sourced after common.sh, never run.
#
# Every find step points at the prefix, so no system imaging library is
# linked in. libtiff is configured without JBIG: JBIG-KIT is
# GPL-2.0-or-later and never ships as object code.

NATIVE_PREFIX="$WORK/prefix"

ZLIB_VERSION="1.3.1"
ZLIB_SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz"
PNG_VERSION="1.6.43"
PNG_SHA256="6a5ca0652392a2d7c9db2ae5b40210843c0bbc081cbd410825ab00cc59f14a6c"
PNG_URL="https://download.sourceforge.net/libpng/libpng-$PNG_VERSION.tar.xz"
JPEG_VERSION="3.0.3"
JPEG_SHA256="343e789069fc7afbcdfe44dbba7dbbf45afa98a15150e079a38e60e44578865d"
JPEG_URL="https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VERSION/libjpeg-turbo-$JPEG_VERSION.tar.gz"
TIFF_VERSION="4.6.0"
TIFF_SHA256="88b3979e6d5c7e32b50d7ec72fb15af724f6ab2cbf7e10880c360a77e4b5d99a"
TIFF_URL="https://download.osgeo.org/libtiff/tiff-$TIFF_VERSION.tar.gz"
LEPT_VERSION="1.84.1"
LEPT_SHA256="2b3e1254b1cca381e77c819b59ca99774ff43530209b9aeb511e1d46588a64f6"
LEPT_URL="https://github.com/DanBloomberg/leptonica/releases/download/$LEPT_VERSION/leptonica-$LEPT_VERSION.tar.gz"

build_native_deps() {
  require_tool gcc g++ make tar xz readelf
  build_tools
  mkdir -p "$NATIVE_PREFIX"
  export CFLAGS="-O2 -fPIC"
  export CXXFLAGS="-O2 -fPIC"
  export PKG_CONFIG_LIBDIR="$NATIVE_PREFIX/lib/pkgconfig"
  export PKG_CONFIG_PATH=""

  ZLIB_SRC="$(unpack "$(fetch_verified "$ZLIB_URL" "$ZLIB_SHA256" "zlib-$ZLIB_VERSION.tar.gz")")"
  (cd "$ZLIB_SRC" && ./configure --prefix="$NATIVE_PREFIX" && make -j"$JOBS" && make install)

  PNG_SRC="$(unpack "$(fetch_verified "$PNG_URL" "$PNG_SHA256" "libpng-$PNG_VERSION.tar.xz")")"
  (cd "$PNG_SRC" && ./configure --prefix="$NATIVE_PREFIX" --disable-static \
      CPPFLAGS="-I$NATIVE_PREFIX/include" LDFLAGS="-L$NATIVE_PREFIX/lib" &&
    make -j"$JOBS" && make install)

  JPEG_SRC="$(unpack "$(fetch_verified "$JPEG_URL" "$JPEG_SHA256" "libjpeg-turbo-$JPEG_VERSION.tar.gz")")"
  # WITH_SIMD=0: the SIMD path needs an assembler this build does not assume.
  (cd "$JPEG_SRC" && "$CMAKE" -S . -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$NATIVE_PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
      -DENABLE_STATIC=OFF -DWITH_JPEG8=ON -DWITH_SIMD=0 -DWITH_TURBOJPEG=OFF &&
    "$CMAKE" --build build -j"$JOBS" && "$CMAKE" --install build)

  TIFF_SRC="$(unpack "$(fetch_verified "$TIFF_URL" "$TIFF_SHA256" "tiff-$TIFF_VERSION.tar.gz")")"
  (cd "$TIFF_SRC" && ./configure --prefix="$NATIVE_PREFIX" --disable-static \
      --disable-jbig --disable-lzma --disable-zstd --disable-webp --disable-lerc \
      --disable-libdeflate --disable-jpeg12 --disable-cxx --disable-tools \
      --disable-tests --disable-contrib --disable-docs \
      --with-zlib-include-dir="$NATIVE_PREFIX/include" --with-zlib-lib-dir="$NATIVE_PREFIX/lib" \
      --with-jpeg-include-dir="$NATIVE_PREFIX/include" --with-jpeg-lib-dir="$NATIVE_PREFIX/lib" &&
    make -j"$JOBS" && make install)

  LEPT_SRC="$(unpack "$(fetch_verified "$LEPT_URL" "$LEPT_SHA256" "leptonica-$LEPT_VERSION.tar.gz")")"
  (cd "$LEPT_SRC" && "$CMAKE" -S . -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$NATIVE_PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_PREFIX_PATH="$NATIVE_PREFIX" -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
      -DBUILD_SHARED_LIBS=ON -DSW_BUILD=OFF -DBUILD_PROG=OFF \
      -DENABLE_GIF=OFF -DENABLE_WEBP=OFF -DENABLE_OPENJPEG=OFF \
      -DENABLE_ZLIB=ON -DENABLE_PNG=ON -DENABLE_JPEG=ON -DENABLE_TIFF=ON \
      -DZLIB_LIBRARY="$NATIVE_PREFIX/lib/libz.so" -DZLIB_INCLUDE_DIR="$NATIVE_PREFIX/include" \
      -DPNG_LIBRARY="$NATIVE_PREFIX/lib/libpng16.so" -DPNG_PNG_INCLUDE_DIR="$NATIVE_PREFIX/include" \
      -DJPEG_LIBRARY="$NATIVE_PREFIX/lib/libjpeg.so" -DJPEG_INCLUDE_DIR="$NATIVE_PREFIX/include" \
      -DTIFF_LIBRARY="$NATIVE_PREFIX/lib/libtiff.so" -DTIFF_INCLUDE_DIR="$NATIVE_PREFIX/include" &&
    "$CMAKE" --build build -j"$JOBS" && "$CMAKE" --install build)
}

# stage_native_deps -> the imaging libraries into lib/, their notices into
# licenses/, and their NOTICES.tsv rows and file map lines.
stage_native_deps() {
  map="$1"
  for lib in libleptonica.so libtiff.so libpng16.so libjpeg.so libz.so; do
    copy_soname "$NATIVE_PREFIX/lib/$lib" "$STAGE/lib"
  done
  for f in "$STAGE"/lib/libleptonica.so.* "$STAGE"/lib/libtiff.so.* "$STAGE"/lib/libpng16.so.* \
      "$STAGE"/lib/libjpeg.so.* "$STAGE"/lib/libz.so.*; do
    case "$(basename "$f")" in
      libleptonica*) c=leptonica ;; libtiff*) c=libtiff ;; libpng16*) c=libpng ;;
      libjpeg*) c=libjpeg-turbo ;; libz*) c=zlib ;;
    esac
    printf '%s\t%s\n' "$(basename "$f")" "$c" >> "$map"
  done
  cp "$LEPT_SRC/leptonica-license.txt" "$STAGE/licenses/LICENSE-leptonica.txt"
  cp "$TIFF_SRC/LICENSE.md" "$STAGE/licenses/LICENSE-libtiff.txt"
  cp "$PNG_SRC/LICENSE" "$STAGE/licenses/LICENSE-libpng.txt"
  cat "$JPEG_SRC/LICENSE.md" "$JPEG_SRC/README.ijg" > "$STAGE/licenses/LICENSE-libjpeg-turbo.txt"
  cp "$ZLIB_SRC/LICENSE" "$STAGE/licenses/LICENSE-zlib.txt"
  {
    printf 'leptonica\t%s\tBSD-2-Clause\thttps://github.com/DanBloomberg/leptonica\tLICENSE-leptonica.txt\n' "$LEPT_VERSION"
    printf 'libtiff\t%s\tlibtiff\thttps://gitlab.com/libtiff/libtiff\tLICENSE-libtiff.txt\n' "$TIFF_VERSION"
    printf 'libpng\t%s\tlibpng-2.0\thttps://github.com/pnggroup/libpng\tLICENSE-libpng.txt\n' "$PNG_VERSION"
    printf 'libjpeg-turbo\t%s\tIJG AND BSD-3-Clause AND Zlib\thttps://github.com/libjpeg-turbo/libjpeg-turbo\tLICENSE-libjpeg-turbo.txt\n' "$JPEG_VERSION"
    printf 'zlib\t%s\tZlib\thttps://github.com/madler/zlib\tLICENSE-zlib.txt\n' "$ZLIB_VERSION"
  } >> "$STAGE/NOTICES.tsv"
}
