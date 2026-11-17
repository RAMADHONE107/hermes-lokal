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
# --dereference/--hard-dereference keep the archive to regular files and
# directories, matching the minimal extractor in HermesTar.kt.
tar --format=ustar --dereference --hard-dereference -czf "$BUNDLE" -C "$STAGE/runtime" .
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
