# Spectra PDF Linux build of jbig2enc

This branch (`spectra-build`) is the upstream tag `0.32` plus added build files. It builds a relocatable Linux x86-64 `jbig2` encoder for Spectra PDF.

## What differs from upstream

- No upstream file is changed. The build files are added:
  - `.github/workflows/spectra-linux.yml`: one job that builds and publishes the release.
  - `spectra/pins.env`: the upstream tag, its commit, and the Spectra build number.
  - `spectra/build.sh`, `spectra/common.sh`, `spectra/linux-native-deps.sh`: the build.
  - `spectra/licenses/LICENSE-gcc-runtime.txt`: the notice for the shipped GCC runtime.
- The workflow refuses to build when the tree outside `spectra/` and the workflow file differs from the pinned upstream commit.
- No define differs from the upstream CMake defaults. `libjbig2enc` links statically into `jbig2`.
- The imaging stack (zlib 1.3.1, libpng 1.6.43, libjpeg-turbo 3.0.3, libtiff 4.6.0 without JBIG, Leptonica 1.84.1) is built in the workflow from SHA-256-pinned release archives.
- The build runs in `quay.io/pypa/manylinux_2_28_x86_64`, pinned by digest. The release notes state the measured glibc floor.

## Artifact

Release tag `spectra-<upstream version>-<n>`. Asset `jbig2enc-<version>-linux-x86_64.tar.zst`:

- `bin/jbig2` (RUNPATH `$ORIGIN/../lib`)
- `lib/`: Leptonica, libtiff, libpng, libjpeg, zlib, `libstdc++.so.6`, `libgcc_s.so.1` (RUNPATH `$ORIGIN`)
- `licenses/`, including `PATENTS-jbig2enc.txt` (upstream `doc/PATENTS`)
- `NOTICES.tsv` (component, version, license, upstream, notices), `SHA256SUMS.txt`

## Sync with upstream

1. `git remote add upstream https://github.com/agl/jbig2enc.git` (once).
2. `git fetch upstream --tags`
3. `git checkout spectra-build && git merge <new tag>`
4. In `spectra/pins.env`, set `UPSTREAM_TAG`, `UPSTREAM_COMMIT` (`git rev-parse <new tag>^{commit}`) and `UPSTREAM_VERSION`. Set `SPECTRA_BUILD=1`.
5. Push `spectra-build`. The workflow builds and publishes `spectra-<new version>-1`.

To rebuild the same upstream version, increase `SPECTRA_BUILD` and push. A published build number is never reused.

## How Spectra pins the artifact

Spectra records the release asset URL, its SHA-256 and its size. The Spectra fetch step downloads the asset, refuses a hash mismatch, and checks `SHA256SUMS.txt` inside the tarball.
