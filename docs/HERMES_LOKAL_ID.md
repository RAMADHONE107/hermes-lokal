# Hermes Lokal — panduan (Bahasa Indonesia)

## Apa ini?

Fork [Ares](https://github.com/rusty4444/ares) (dulu Hermes Android) yang
ditambah opsi koneksi **Hermes Lokal**. Ares adalah *client* Flutter; engine
Hermes Agent tetap harus berjalan di suatu tempat. Di fork ini engine tersebut
hidup **di dalam HP yang sama**, memakai Termux + proot Ubuntu.

```
[ APK Hermes Lokal ]  --127.0.0.1:8642-->  [ proot Ubuntu di Termux ]  --> [ Hermes Agent ]
```

proot memakai network namespace Android yang sama, jadi gateway hanya perlu
mendengar di loopback. Tidak ada port yang dibuka ke Wi-Fi/LAN.

## Prasyarat di HP

- Android 11+ (arm64 / `aarch64`)
- Termux dari F-Droid (bukan versi Play Store yang sudah tidak dirawat)
- Ruang kosong minimal 5 GB (rootfs Ubuntu + Python + Node + model)
- RAM 4 GB atau lebih disarankan
- Koneksi internet saat instalasi
- Paket `hermes-agent` APT resmi sedang bermasalah menurut dokumentasi
  upstream, maka jalur proot Ubuntu yang dipakai di sini

## 1. Build APK

1. Fork repo ini ke akun GitHub sendiri, atau buat repo baru lalu push isi
   folder ini ke branch `main`.
2. Buka tab **Actions** di repo tersebut → izinkan workflow.
3. Workflow **Build Hermes Lokal APK** jalan otomatis saat push ke `main`.
   Bisa juga dipicu manual lewat **Run workflow**.
4. Setelah selesai, buka artefak `hermes-lokal-arm64-v8a`, download, lalu
   buka di HP (izinkan *Install unknown apps* untuk file manager/browser).

Workflow ini **sengaja terpisah** dari `release.yml` upstream. File itu
mensyaratkan keystore pribadi maintainer dan tag rilis persis `v4.0.4`, jadi
tidak akan pernah berhasil di fork.

> Keystore di workflow dibuat sendiri dengan password tetap
> `hermes-lokal-local-build`. Itu cukup untuk sideload pribadi. Ganti dengan
> GitHub Secrets sebelum membagikan APK ke orang lain.

## 2. Pasang engine di HP

Buka Termux, lalu dari folder repo yang sudah di-clone di HP:

```bash
pkg install -y git
git clone <URL_REPO_FORK_KAMU> ~/hermes-lokal
cd ~/hermes-lokal
bash scripts/install-local-hermes.sh install
```

Script akan memasang proot-distro, Ubuntu, lalu Hermes Agent di dalamnya.
Setelah itu konfigurasi provider/model sekali saja:

```bash
proot-distro login ubuntu
hermes setup
exit
```

Lalu jalankan gateway:

```bash
cd ~/hermes-lokal
bash scripts/install-local-hermes.sh start
bash scripts/install-local-hermes.sh status
```

Perintah `start` mencetak `API_SERVER_KEY` dari `~/.hermes/.env` di dalam
rootfs. Simpan nilai itu sebentar — tidak perlu dibagikan ke siapa pun.

Agar proses tidak dimatikan Android saat layar mati:

```bash
pkg install -y termux-api
termux-wake-lock
```

Matikan juga battery optimization untuk Termux di Settings Android.

## 3. Hubungkan dari APK

1. Buka **Hermes Lokal**.
2. Tekan tombol **+** → pilih **Hermes Lokal**.
3. Kolom Host, Port, dan Label sudah terisi (`127.0.0.1`, `8642`).
4. Tempel `API_SERVER_KEY` dari langkah sebelumnya ke kolom API Key.
5. Simpan, lalu buka sesi/chat.

Opsi ini hanya men-provide default. Kamu masih bisa menambah koneksi remote
biasa lewat menu **Add Connection** yang lama.

## Masalah umum

| Gejala | Penyebab / solusi |
| --- | --- |
| `status` bilang MATI setelah `start` | Lihat `~/.hermes/logs/gateway.log` di dalam `proot-distro login ubuntu`. Kemungkinan `hermes setup` belum dijalankan. |
| APK tidak bisa install | HP belum mengizinkan install dari sumber unknown, atau APK x86_64 yang terdownload. Pakai artefak `arm64-v8a`. |
| Chat terputus saat layar mati | Android mematikan proses latar belakang. Pakai `termux-wake-lock` + matikan battery optimization. |
| Ingin update engine | Di dalam Ubuntu: `hermes update`. Ini tidak mengubah APK. |
| Ingin update APK | Push perubahan ke `main`, unduh artefak baru, install di atas yang lama (keystore sama). |

## Batasan yang disadari

- Engine tidak benar-benar "di dalam APK". Android tidak bisa menjalankan
  Python/Node + wheel native langsung dari APK; Termux + proot tetap dibutuhkan.
- Tidak ada dukungan voice/wake-word lokal lewat Termux:API dari paket APT
  upstream (disebutkan di dokumentasi resmi).
- Browser/computer-use tidak tersedia kecuali Chromium dipasang di rootfs.
- Ini fork komunitas, bukan rilis resmi Nous Research.
