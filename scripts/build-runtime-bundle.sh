#!/data/data/com.termux/files/usr/bin/bash
# Build the offline runtime bundle used by the embedded Hermes engine.
# Run this on a device with Termux + proot-distro's Ubuntu container installed.
set -euo pipefail

OUT_DIR="${1:-$HOME/hermes-bundle}"
VERSION="${2:-local-$(date +%Y%m%d%H%M)}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
ROOTFS="${ROOTFS:-$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs}"

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

cp -a "$ROOTFS" "$STAGE/runtime/rootfs"
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
  echo "  proot-distro login ubuntu -- apt-get update && apt-get install -y python3 python3-pip" >&2
  exit 1
fi

SIZE=$(du -sb "$STAGE/runtime" | cut -f1)
tar --format=ustar --dereference -czf "$BUNDLE" -C "$STAGE" runtime
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
