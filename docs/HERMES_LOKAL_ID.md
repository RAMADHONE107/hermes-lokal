# Hermes Lokal — panduan (Bahasa Indonesia)

## Apa ini?

Fork [Ares](https://github.com/rusty4444/ares) yang ditambah opsi koneksi
**Hermes Lokal**. Bedanya dengan panduan lama: engine Hermes **tidak lagi
dijalankan dari Termux yang berdiri sendiri**. Runtime-nya diunduh sekali,
disimpan di storage privat aplikasi, dan dijalankan oleh foreground service
milik APK ini sendiri.

```
[ APK Hermes Lokal ]
   ├─ UI Flutter (Ares)
   ├─ HermesEngineService (foreground)
   └─ files/hermes-runtime/
        ├─ proot + loader
        └─ rootfs Ubuntu + Python + Hermes Agent
                │
                └─ 127.0.0.1:8642 → /v1/chat/completions
```

Dari sisi pemakai: buka aplikasi, tekan **Kelola Mesin Lokal**, siapkan,
mulai, lalu chat. Tidak perlu membuka Termux.

Desain lengkap: [`HERMES_EMBEDDED_DESIGN_ID.md`](HERMES_EMBEDDED_DESIGN_ID.md).

## Prasyarat

- Android 11+ (arm64 / `aarch64`)
- Ruang kosong ±2 GB untuk runtime (bundle ~276 MB, hasil ekstrak ~830 MB)
- RAM 4 GB atau lebih disarankan
- Internet hanya saat first run / saat mengunduh bundle runtime

## 1. Build APK

1. Push perubahan ke branch `main` repo `RAMADHONE107/hermes-lokal`.
2. Buka tab **Actions** → workflow **Build Hermes Lokal APK**.
3. Setelah selesai, unduh artefak `hermes-lokal-arm64-v8a`, lalu install di HP
   (izinkan *Install unknown apps*).

Workflow ini sengaja terpisah dari `release.yml` upstream karena butuh
keystore pribadi maintainer dan tag `v4.0.4`.

> APK ditandatangani dengan keystore permanen yang disimpan sebagai GitHub
> Secrets `SIGNING_KEYSTORE_BASE64` dan `SIGNING_KEYSTORE_PASSWORD`. Ini
> penting agar update berikutnya bisa mengganti versi terpasang tanpa error
> "paket tidak valid". Jangan buang kedua secret tersebut.

## 2. Siapkan bundle runtime (developer)

Bundle tidak ikut di APK supaya ukuran APK tetap ~100 MB. Bundle dibuat di
perangkat Termux lalu di-upload sebagai GitHub Release asset.

```bash
pkg install -y proot-distro
proot-distro install ubuntu:24.04 --name ubuntu2404
proot-distro login ubuntu2404
  apt-get update
  apt-get install -y python3 python3-pip nodejs npm git ripgrep ffmpeg ca-certificates curl
  python3 -m pip install hermes-agent==0.19.0 'aiohttp==3.14.1'
  exit

cd ~/hermes-lokal
bash scripts/build-runtime-bundle.sh ~/hermes-bundle v0.2.0-runtime
gh release create v0.2.0-runtime \
  ~/hermes-bundle/hermes-runtime-arm64-v8a.tar.gz \
  --repo RAMADHONE107/hermes-lokal \
  --title "Hermes runtime arm64" \
  --notes "Offline runtime bundle for Hermes Lokal"
```

Salin `sha256` dan `sizeBytes` dari `~/hermes-bundle/runtime-manifest.json`
ke `android/app/src/main/assets/hermes/runtime-manifest.json`, lalu build ulang APK.

Script hanya menyalin rootfs ke stage, memangkas paket yang tidak diperlukan
server API headless (LLVM, Mesa, gcc, perl, modul node, ikon, dll), lalu
membuat tar dengan symlink utuh. Ekstraktor di APK menulis ulang target
symlink absolut ke path relatif di dalam `rootfs`, jadi runtime hasil ekstrak
bisa dipakai tanpa Termux.

> Status saat ini: release `v0.2.0-runtime` sudah berisi bundle arm64 dan
> manifest di APK sudah mengacu ke SHA-256-nya. Runtime diverifikasi sekali
> saat download, lalu dipakai offline.

## 3. Pakai di HP

1. Buka **Hermes Lokal**.
2. Tekan **+** → **Kelola Mesin Lokal**.
3. Tekan **Siapkan**. Tunggu progress unduh + ekstrak selesai.
4. Tekan **Mulai**. Status berubah menjadi **Berjalan**.
5. Kembali ke **+** → **Hermes Lokal**. Host, port, dan API key sudah terisi
   otomatis. Simpan koneksi.
6. Buka chat dan bicara seperti biasa.

API key dibuat lokal (32 byte hex) dan hanya disimpan di
`files/hermes-data/.env`. Tidak pernah dikirim ke server kita.

## 4. Konfigurasi provider / model

Hermes masih butuh provider LLM. Dua jalur:

- Pakai UI Ares yang sudah ada untuk mengubah provider/model lewat gateway.
- Atau, saat runtime sudah terpasang, jalankan setup sekali dari dalam
  rootfs memakai terminal apa pun yang bisa mengeksekusi bundle (misalnya
  lewat mode diagnostic yang akan ditambahkan di phase 2).

Untuk MVP, API key provider bisa ditaruh di `.env` rootfs sebelum bundle
dibuat, atau lewat perintah `hermes setup` saat build bundle.

## Masalah umum

| Gejala | Penyebab / solusi |
| --- | --- |
| **Siapkan** gagal "Checksum runtime tidak cocok" | Manifest belum diperbarui setelah upload bundle, atau file unduhan korup. |
| **Siapkan** gagal "Unduh gagal (HTTP 404)" | Asset release belum di-upload / URL di manifest salah. |
| **Mulai** gagal "Runtime tidak lengkap" | Ekstrak tidak selesai. Hapus data aplikasi lalu siapkan ulang. |
| Chat tidak balas | Gateway belum `RUNNING`, atau provider belum dikonfigurasi. Cek **Log mesin**. |
| Mesin mati sendiri | Matikan battery optimization untuk Hermes Lokal di Settings Android. |
| Ingin update engine | Build bundle baru, upload, perbarui manifest, build ulang APK. |

## Batasan yang disadari

- MVP hanya mendukung `arm64-v8a`.
- Runtime diunduh sekali; belum ada self-update dari dalam aplikasi.
- OAuth Nous Portal belum punya UI khusus di panel mesin.
- Ini fork komunitas, bukan rilis resmi Nous Research.
