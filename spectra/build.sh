#!/bin/sh
# Builds the jbig2 encoder for Linux x86-64 from this checkout and the pinned
# imaging stack, then packages bin/, lib/, licenses/ (with the PATENTS notice),
# NOTICES.tsv and SHA256SUMS.txt.

. "$(dirname "$0")/common.sh"
. "$SPECTRA_DIR/linux-native-deps.sh"
require_tool objdump zstd rpm

rm -rf "$WORK/build" "$WORK/install" "$STAGE"
build_native_deps

"$CMAKE" -S "$SOURCE_ROOT" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$WORK/install" -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_PREFIX_PATH="$NATIVE_PREFIX" -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
  -DLeptonica_DIR="$NATIVE_PREFIX/lib/cmake/leptonica" -DBUILD_SHARED_LIBS=OFF
"$CMAKE" --build "$WORK/build" -j"$JOBS"
"$CMAKE" --install "$WORK/build"

mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/share" "$STAGE/licenses"
map="$WORK/file-map.tsv"
: > "$map"
printf 'component\tversion\tlicense\tupstream\tnotices\n' > "$STAGE/NOTICES.tsv"

cp "$WORK/install/bin/jbig2" "$STAGE/bin/jbig2"
printf 'jbig2\tjbig2enc\n' >> "$map"
cp "$SOURCE_ROOT/COPYING" "$STAGE/licenses/LICENSE-jbig2enc.txt"
cp "$SOURCE_ROOT/doc/PATENTS" "$STAGE/licenses/PATENTS-jbig2enc.txt"
printf 'jbig2enc\t%s\tApache-2.0\t%s\tLICENSE-jbig2enc.txt,PATENTS-jbig2enc.txt\n' "$UPSTREAM_VERSION" "$UPSTREAM_REPO" >> "$STAGE/NOTICES.tsv"

stage_native_deps "$map"
stage_gcc_runtime "$WORK/install/bin/jbig2" "$map"
rmdir "$STAGE/share"

set_runpaths
check_needed
notice_gate "$map"

got="$("$STAGE/bin/jbig2" --version 2>&1 | head -n1)"
[ "$got" = "jbig2enc $UPSTREAM_VERSION" ] || die "the staged program reports '$got', not jbig2enc $UPSTREAM_VERSION"

package jbig2enc
