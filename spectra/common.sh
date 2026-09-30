# Shared helpers for the Spectra Linux build. Sourced, never run.
#
# WORK is the scratch root (downloads, sources, prefixes, stage). STAGE is the
# tree that becomes the release tarball: bin/, lib/, share/, licenses/,
# NOTICES.tsv, SHA256SUMS.txt.

set -eu

SPECTRA_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$(cd "$SPECTRA_DIR/.." && pwd)"
WORK="${SPECTRA_WORK:-$SOURCE_ROOT/.spectra-work}"
FETCH_CACHE="$WORK/downloads"
STAGE="$WORK/stage"
OUT="${SPECTRA_OUT:-$SOURCE_ROOT/.spectra-out}"
JOBS="$(nproc 2>/dev/null || echo 2)"
FETCH_ATTEMPTS=4

. "$SPECTRA_DIR/pins.env"

CMAKE_WHEEL="cmake-3.31.6-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
CMAKE_WHEEL_SHA256="1c8b05df0602365da91ee6a3336fe57525b137706c4ab5675498f662ae1dbcec"
CMAKE_WHEEL_URL="https://files.pythonhosted.org/packages/59/e8/096984b89133681533650b9078c5ed1c5c9b534e869b5487f22d4de1935c/$CMAKE_WHEEL"
PATCHELF_WHEEL="patchelf-0.17.2.4-py3-none-manylinux1_x86_64.manylinux_2_5_x86_64.musllinux_1_1_x86_64.whl"
PATCHELF_WHEEL_SHA256="d9b35ebfada70c02679ad036407d9724ffe1255122ba4ac5e4be5868618a5689"
PATCHELF_WHEEL_URL="https://files.pythonhosted.org/packages/7e/19/f7821ef31aab01fa7dc8ebe697ece88ec4f7a0fdd3155dab2dfee4b00e5c/$PATCHELF_WHEEL"

# The C runtime every glibc system provides. Anything else a shipped file
# needs must ship in lib/.
SYSTEM_SONAMES="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 ld-linux-x86-64.so.2"

die() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required on PATH"
  done
}

sha256_of() {
  sha256sum "$1" | cut -d' ' -f1
}

# fetch_verified URL SHA256 NAME -> prints the cached path. A download whose
# hash differs from the pin refuses.
fetch_verified() {
  url="$1"; want="$2"; name="$3"
  mkdir -p "$FETCH_CACHE"
  path="$FETCH_CACHE/$name"
  if [ -f "$path" ] && [ "$(sha256_of "$path")" = "$want" ]; then
    echo "$path"
    return 0
  fi
  rm -f "$path" "$path.part"
  attempt=1
  while :; do
    if curl -fsSL --connect-timeout 30 --max-time 1800 -o "$path.part" "$url" >&2; then
      break
    fi
    [ "$attempt" -ge "$FETCH_ATTEMPTS" ] && die "download failed after $attempt attempts: $url"
    sleep $((attempt * 3))
    attempt=$((attempt + 1))
  done
  got="$(sha256_of "$path.part")"
  if [ "$got" != "$want" ]; then
    rm -f "$path.part"
    die "$name has SHA-256 $got; the pin is $want"
  fi
  mv "$path.part" "$path"
  echo "$path"
}

# unpack ARCHIVE -> prints the fresh source directory under $WORK/src.
unpack() {
  mkdir -p "$WORK/src"
  top="$(tar -tf "$1" | head -n1 | cut -d/ -f1)"
  rm -rf "${WORK:?}/src/$top"
  tar -xf "$1" -C "$WORK/src"
  echo "$WORK/src/$top"
}

# build_tools -> CMAKE and PATCHELF from the pinned wheels.
build_tools() {
  tools="$WORK/tools"
  if [ ! -x "$tools/bin/cmake" ] || [ ! -x "$tools/bin/patchelf" ]; then
    require_tool python3
    rm -rf "$tools"
    python3 -m venv --without-pip "$tools"
    cm="$(fetch_verified "$CMAKE_WHEEL_URL" "$CMAKE_WHEEL_SHA256" "$CMAKE_WHEEL")"
    pe="$(fetch_verified "$PATCHELF_WHEEL_URL" "$PATCHELF_WHEEL_SHA256" "$PATCHELF_WHEEL")"
    site="$("$tools/bin/python3" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
    "$tools/bin/python3" -m zipfile -e "$cm" "$site"
    "$tools/bin/python3" -m zipfile -e "$pe" "$site"
    chmod +x "$site"/cmake/data/bin/* 2>/dev/null || true
    [ -x "$site/cmake/data/bin/cmake" ] || die "the cmake wheel layout changed: no cmake/data/bin/cmake"
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$site/cmake/data/bin/cmake" > "$tools/bin/cmake"
    chmod +x "$tools/bin/cmake"
    pe_bin=""
    for candidate in "$site"/patchelf-*.data/scripts/patchelf "$site"/patchelf/bin/patchelf; do
      [ -f "$candidate" ] && { pe_bin="$candidate"; break; }
    done
    [ -n "$pe_bin" ] || die "the patchelf wheel layout changed: no patchelf program"
    cp "$pe_bin" "$tools/bin/patchelf"
    chmod +x "$tools/bin/patchelf"
  fi
  CMAKE="$tools/bin/cmake"
  PATCHELF="$tools/bin/patchelf"
}

is_elf() {
  [ -f "$1" ] && [ "$(head -c4 "$1" | tail -c3)" = "ELF" ]
}

# copy_soname LIBRARY_PATH DEST_DIR -> copies the real file under its SONAME.
copy_soname() {
  real="$(readlink -f "$1")"
  soname="$(readelf -d "$real" | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')"
  [ -n "$soname" ] || die "$1 has no SONAME"
  cp "$real" "$2/$soname"
  chmod 0755 "$2/$soname"
}

# copy_gcc_runtime ELF_FILE DEST_DIR -> copies libstdc++.so.6 and libgcc_s.so.1
# from the paths the loader resolves for ELF_FILE.
copy_gcc_runtime() {
  for runtime in libstdc++.so.6 libgcc_s.so.1; do
    path="$(LD_LIBRARY_PATH="$2" ldd "$1" | awk -v n="$runtime" '$1 == n { print $3; exit }')"
    case "$path" in "$2"/*) path="" ;; esac
    [ -n "$path" ] || path="$(/sbin/ldconfig -p | awk -v n="$runtime" '$1 == n && /x86-64/ { print $NF; exit }')"
    [ -n "$path" ] && [ -f "$path" ] || die "cannot locate $runtime for $1"
    cp -L "$path" "$2/$runtime"
    chmod 0755 "$2/$runtime"
  done
}

# stage_gcc_runtime ELF_FILE MAP -> the GCC runtime into lib/ with its notice,
# NOTICES.tsv row and file map lines.
stage_gcc_runtime() {
  copy_gcc_runtime "$1" "$STAGE/lib"
  gcc_version="$(rpm -qf --qf '%{VERSION}\n' "$(readlink -f "$(/sbin/ldconfig -p | awk '$1 == "libstdc++.so.6" && /x86-64/ { print $NF; exit }')")" | head -n1)"
  [ -n "$gcc_version" ] || die "cannot read the GCC runtime version"
  cp "$SPECTRA_DIR/licenses/LICENSE-gcc-runtime.txt" "$STAGE/licenses/LICENSE-gcc-runtime.txt"
  printf 'libstdc++.so.6\tgcc-runtime\nlibgcc_s.so.1\tgcc-runtime\n' >> "$2"
  printf 'gcc-runtime\t%s\tGPL-3.0-or-later WITH GCC-exception-3.1\thttps://gcc.gnu.org\tLICENSE-gcc-runtime.txt\n' "$gcc_version" >> "$STAGE/NOTICES.tsv"
}

# set_runpaths ->bin/ resolves in ../lib, lib/ resolves beside itself.
set_runpaths() {
  for f in "$STAGE"/bin/* "$STAGE"/lib/*; do
    is_elf "$f" || continue
    case "$f" in
      "$STAGE"/bin/*) "$PATCHELF" --set-rpath '$ORIGIN/../lib' "$f" ;;
      *) "$PATCHELF" --set-rpath '$ORIGIN' "$f" ;;
    esac
  done
}

# check_needed -> refuses a NEEDED entry that is neither in lib/ nor part of
# the C runtime, and any reference to JBIG-KIT.
check_needed() {
  problems=""
  for f in "$STAGE"/bin/* "$STAGE"/lib/*; do
    is_elf "$f" || continue
    for need in $(readelf -d "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
      case "$need" in libjbig*) problems="$problems
  $(basename "$f") needs $need (JBIG-KIT is GPL object code)";; esac
      [ -f "$STAGE/lib/$need" ] && continue
      case " $SYSTEM_SONAMES " in *" $need "*) continue ;; esac
      problems="$problems
  $(basename "$f") needs $need, which is neither shipped nor part of the C runtime"
    done
  done
  [ -z "$problems" ] || die "dependency gate refused:$problems"
}

# notice_gate MAP -> MAP lines are "file<TAB>component". Every shipped ELF file
# needs a line, every component needs a NOTICES.tsv row, and every notice the
# row names must be present under licenses/.
notice_gate() {
  map="$1"
  problems=""
  for f in "$STAGE"/bin/* "$STAGE"/lib/*; do
    is_elf "$f" || continue
    name="$(basename "$f")"
    component="$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$map")"
    if [ -z "$component" ]; then
      problems="$problems
  $name: shipped with no component"
      continue
    fi
    row="$(awk -F'\t' -v c="$component" 'NR > 1 && $1 == c' "$STAGE/NOTICES.tsv")"
    [ -n "$row" ] || problems="$problems
  $name: component $component has no NOTICES.tsv row"
  done
  while IFS="$(printf '\t')" read -r component version license url notices; do
    [ "$component" = "component" ] && continue
    for notice in $(echo "$notices" | tr ',' ' '); do
      [ -f "$STAGE/licenses/$notice" ] || problems="$problems
  $component: notice licenses/$notice is not present"
    done
  done < "$STAGE/NOTICES.tsv"
  [ -z "$problems" ] || die "notice gate refused:$problems"
}

# glibc_floor -> the highest GLIBC_ symbol version any shipped ELF file needs.
glibc_floor() {
  for f in "$STAGE"/bin/* "$STAGE"/lib/*; do
    is_elf "$f" || continue
    objdump -T "$f"
  done > "$WORK/objdump-T.txt"
  grep -o 'GLIBC_[0-9.]*' "$WORK/objdump-T.txt" > "$WORK/glibc-versions.txt"
  sort -u -V "$WORK/glibc-versions.txt" > "$WORK/glibc-sorted.txt"
  tail -n1 "$WORK/glibc-sorted.txt"
}

# package NAME -> writes SHA256SUMS.txt into the stage, then
# $OUT/NAME-VERSION-linux-x86_64.tar.zst plus release metadata.
package() {
  name="$1"
  floor="$(glibc_floor)"
  [ -n "$floor" ] || die "no GLIBC_ symbol version found in the shipped files"
  (cd "$STAGE" && find . -type f ! -name SHA256SUMS.txt | LC_ALL=C sort | sed 's|^\./||' |
    while read -r rel; do sha256sum "$rel"; done > SHA256SUMS.txt)
  mkdir -p "$OUT"
  asset="$name-$UPSTREAM_VERSION-linux-x86_64.tar.zst"
  epoch="${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH must be the pinned commit time}"
  tar -C "$STAGE" --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$epoch" \
    -cf "$WORK/$name.tar" .
  zstd -q -19 -f "$WORK/$name.tar" -o "$OUT/$asset"
  echo "$asset" > "$OUT/asset-name.txt"
  sha256_of "$OUT/$asset" > "$OUT/asset-sha256.txt"
  stat -c %s "$OUT/$asset" > "$OUT/asset-size.txt"
  echo "$floor" > "$OUT/glibc-floor.txt"
  echo "Packaged $asset: sha256 $(cat "$OUT/asset-sha256.txt"), $(cat "$OUT/asset-size.txt") bytes, floor $floor"
}
