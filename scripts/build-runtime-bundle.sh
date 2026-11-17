#!/data/data/com.termux/files/usr/bin/bash
# Build the offline runtime bundle used by the embedded Hermes engine.
# Run this on a device with Termux + proot-distro's Ubuntu container installed.
set -euo pipefail

OUT_DIR="${1:-$HOME/hermes-bundle}"
VERSION="${2:-local-$(date +%Y%m%d%H%M)}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
ROOTFS="${ROOTFS:-$PREFIX/var/lib/proot-distro/containers/ubuntu2404/rootfs}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }
}
require tar
require gzip
require sha256sum

if [ ! -d "$ROOTFS/usr/bin" ]; then
  echo "Ubuntu rootfs not found at $ROOTFS" >&2
  echo "Install it first: pkg install proot-distro && proot-distro install ubuntu" >&2
  exit 1
fi

STAGE="$OUT_DIR/stage"
BUNDLE="$OUT_DIR/hermes-runtime-arm64-v8a.tar.gz"
rm -rf "$STAGE" "$BUNDLE"
mkdir -p "$STAGE/runtime/bin" "$STAGE/runtime/lib" "$STAGE/runtime/libexec/proot"

cp "$PREFIX/bin/proot" "$STAGE/runtime/bin/proot"
cp -L "$PREFIX/lib/libtalloc.so.2.5.0" "$STAGE/runtime/lib/libtalloc.so.2"
cp -L "$PREFIX/lib/libandroid-shmem.so" "$STAGE/runtime/lib/libandroid-shmem.so"
cp "$PREFIX/libexec/proot/loader" "$PREFIX/libexec/proot/loader32" "$STAGE/runtime/libexec/proot/"

# The launcher bind-mounts /data at runtime, but the empty placeholder inside
# the rootfs can be left mode 0000 by a prior proot bind. Make it copyable.
if [ -d "$ROOTFS/data" ]; then
  chmod -R u+rwX "$ROOTFS/data" 2>/dev/null || true
fi
cp -a "$ROOTFS" "$STAGE/runtime/rootfs"

# Drop package-manager and documentation payloads; they are useless at
# runtime and easily add hundreds of megabytes to the first-run download.
rm -rf "$STAGE/runtime/rootfs/var/lib/apt/lists/"* \
       "$STAGE/runtime/rootfs/var/cache/apt/archives/"*.deb \
       "$STAGE/runtime/rootfs/usr/share/doc/"* \
       "$STAGE/runtime/rootfs/usr/share/man/"* 2>/dev/null || true

# The default Ubuntu container installs a lot of packages that a headless
# Python API server never uses. Remove them from the stage only (the source
# container stays intact) so the first-run download stays reasonable.
R="$STAGE/runtime/rootfs"
rm -rf \
  "$R/usr/lib/aarch64-linux-gnu/libLLVM.so."* \
  "$R/usr/lib/aarch64-linux-gnu/libvulkan_"*.so \
  "$R/usr/lib/aarch64-linux-gnu/dri" \
  "$R/usr/lib/aarch64-linux-gnu/libgallium-"*.so \
  "$R/usr/lib/aarch64-linux-gnu/perl" \
  "$R/usr/lib/aarch64-linux-gnu/perl5" \
  "$R/usr/lib/gcc" \
  "$R/usr/include" \
  "$R/usr/src" \
  "$R/usr/lib/systemd" \
  "$R/usr/share/nodejs" \
  "$R/usr/share/perl" \
  "$R/usr/share/perl5" \
  "$R/usr/share/pocketsphinx" \
  "$R/usr/share/icons" \
  "$R/usr/share/X11" \
  "$R/usr/share/fonts" \
  "$R/usr/share/gtk-3.0" \
  "$R/usr/share/alsa" \
  "$R/usr/share/mime" \
  "$R/usr/share/info" \
  "$R/usr/bin/aarch64-linux-gnu-"* \
  "$R/usr/bin/"*gcc* "$R/usr/bin/"*g++* "$R/usr/bin/"*cpp* \
  "$R/usr/bin/perl"* "$R/usr/bin/lto-dump"* \
  "$R/usr/lib/python3.12/config-"* 2>/dev/null || true
find "$R" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
# Leftover proot-distro symlink-fixup files point at the host Termux prefix.
rm -rf "$R/.l2s" 2>/dev/null || true
find "$R" -type l -lname '/data/data/*' -delete 2>/dev/null || true

mkdir -p "$STAGE/runtime/rootfs/usr/local/bin"

cat > "$STAGE/runtime/rootfs/usr/local/bin/hermes-start.sh" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail
export HOME=/data
export HERMES_HOME=/data
export PYTHONUNBUFFERED=1
export PATH=/usr/local/bin:/usr/bin:/bin
mkdir -p /data/tmp
exec python3 -c "from hermes_cli.main import main; main()" gateway
LAUNCHER
chmod +x "$STAGE/runtime/rootfs/usr/local/bin/hermes-start.sh"

if [ ! -x "$STAGE/runtime/rootfs/usr/bin/python3" ] && [ ! -x "$STAGE/runtime/rootfs/bin/python3" ]; then
  echo "Python3 is missing in the rootfs. Install it first:" >&2
  echo "  proot-distro login ubuntu2404 -- apt-get update && apt-get install -y python3 python3-pip" >&2
  exit 1
fi

# The API server silently refuses to start without aiohttp. Fail the bundle
# build early instead of shipping a runtime whose /health never comes up.
if ! find "$STAGE/runtime/rootfs/usr/lib/python3"* "$STAGE/runtime/rootfs/usr/local/lib/python3"* -maxdepth 3 -type d -name aiohttp 2>/dev/null | grep -q .; then
  echo "aiohttp is missing in the rootfs. Install it first:" >&2
  echo "  proot-distro login ubuntu2404 -- python3 -m pip install 'aiohttp==3.14.1'" >&2
  exit 1
fi

SIZE=$(du -sb "$STAGE/runtime" | cut -f1)
# Do NOT use --dereference: rootfs symlinks such as /usr/bin/X11 -> . recurse
# forever. Symlinks are preserved and recreated safely by HermesTar.kt.
# --hard-dereference turns hardlinks into regular files, which the extractor
# already handles.
tar --format=ustar --hard-dereference -czf "$BUNDLE" -C "$STAGE/runtime" .
SHA=$(sha256sum "$BUNDLE" | cut -d' ' -f1)

cat > "$OUT_DIR/runtime-manifest.json" <<MANIFEST
{
  "version": "$VERSION",
  "url": "https://github.com/RAMADHONE107/hermes-lokal/releases/download/v0.2.0-runtime/hermes-runtime-arm64-v8a.tar.gz",
  "sha256": "$SHA",
  "sizeBytes": $SIZE,
  "hermesVersion": "0.19.0",
  "pythonVersion": "3.12"
}
MANIFEST

echo "Bundle: $BUNDLE"
echo "SHA-256: $SHA"
echo "Manifest: $OUT_DIR/runtime-manifest.json"
