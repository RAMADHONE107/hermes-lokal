#!/usr/bin/env bash
# Hermes Lokal - pasang dan jalankan engine Hermes Agent di dalam HP.
# Engine hidup di rootfs Ubuntu (proot) di bawah Termux. Karena proot memakai
# network namespace yang sama dengan Android, gateway cukup dengar di loopback.
#
# Pemakaian:
#   bash install-local-hermes.sh install   pasang proot Ubuntu + Hermes
#   bash install-local-hermes.sh start     jalankan gateway di 127.0.0.1:8642
#   bash install-local-hermes.sh status    cek apakah gateway aktif
set -euo pipefail

ROOTFS_REL="var/lib/proot-distro/installed-rootfs/ubuntu"
GATEWAY_PORT=8642

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

require_termux() {
  [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || die "Jalankan dari dalam Termux, bukan shell lain."
  command -v pkg >/dev/null 2>&1 || die "Perintah pkg tidak ditemukan."
  [ "$(uname -m)" = "aarch64" ] || die "Script ini hanya untuk perangkat aarch64/arm64."
}

ubuntu_installed() { [ -d "$PREFIX/$ROOTFS_REL" ]; }

install_engine() {
  info "Memasang proot-distro..."
  pkg install -y proot-distro curl

  if ubuntu_installed; then
    info "Rootfs Ubuntu sudah ada, dilewati."
  else
    info "Memasang rootfs Ubuntu (bisa lama, butuh ruang sekitar 1-2 GB)..."
    proot-distro install ubuntu
  fi

  info "Memasang Hermes Agent di dalam Ubuntu..."
  proot-distro login ubuntu -- /bin/bash -s <<'INNER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git
if command -v hermes >/dev/null 2>&1; then
  echo "Hermes sudah terpasang, dilewati."
else
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o /tmp/hermes-install.sh
  bash /tmp/hermes-install.sh --non-interactive --skip-browser --skip-computer-use
fi
hermes --version
INNER

  cat <<EOF

Engine Hermes terpasang.

Langkah berikutnya:
  1. proot-distro login ubuntu
  2. hermes setup          # pilih provider/model, menghasilkan API_SERVER_KEY
  3. exit
  4. bash install-local-hermes.sh start
  5. Di aplikasi Hermes Lokal: + > Hermes Lokal > tempel API_SERVER_KEY

EOF
}

start_gateway() {
  ubuntu_installed || die "Ubuntu belum terpasang. Jalankan dulu: bash install-local-hermes.sh install"
  info "Menjalankan gateway di 127.0.0.1:$GATEWAY_PORT ..."
  proot-distro login ubuntu -- /bin/bash -s <<'INNER'
set -euo pipefail
mkdir -p "$HOME/.hermes/logs"
pidfile="$HOME/.hermes/logs/gateway.pid"
if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  echo "Gateway sudah berjalan (PID $(cat "$pidfile"))."
else
  nohup hermes gateway run >> "$HOME/.hermes/logs/gateway.log" 2>&1 &
  echo $! > "$pidfile"
  echo "Gateway dimulai (PID $!)."
fi
if [ -f "$HOME/.hermes/.env" ]; then
  grep -E '^API_SERVER_KEY=' "$HOME/.hermes/.env" || true
fi
INNER
  info "Log gateway: ~/.hermes/logs/gateway.log (di dalam rootfs ubuntu)"
}

status_gateway() {
  if (exec 3<>"/dev/tcp/127.0.0.1/$GATEWAY_PORT") 2>/dev/null; then
    echo "Gateway 127.0.0.1:$GATEWAY_PORT: AKTIF"
    exec 3<&- 3>&-
  else
    echo "Gateway 127.0.0.1:$GATEWAY_PORT: MATI"
  fi
}

case "${1:-install}" in
  install) require_termux; install_engine ;;
  start)   require_termux; start_gateway ;;
  status)  status_gateway ;;
  -h|--help|help) sed -n '2,10p' "$0" ;;
  *) die "Perintah tidak dikenal: $1 (pilih: install | start | status)" ;;
esac
