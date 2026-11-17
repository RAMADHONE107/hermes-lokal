# Hermes Tertanam di APK — Desain & MVP

Status: **desain disetujui, MVP dalam pembangunan**
Tanggal: 2026-11-17

## 1. Keputusan inti

| Keputusan | Pilihan | Alasan |
|---|---|---|
| Lokasi engine | Di dalam proses APK, storage privat aplikasi | User tidak ingin Termux terpisah |
| Cara runtime dibawa | **Download sekali saat first run**, lalu disimpan offline | APK tetap ~100 MB; after-first-run fully lokal |
| UI | Lanjut Ares (Flutter) | Sudah ada, test hijau, tinggal sambung |
| Komponen GPL/LGPL | Boleh dipakai dengan notice | Jalur realistis satu-satunya |
| Pendekatan runtime | **proot + rootfs Ubuntu** di storage privat | Satu-satunya jalur yang bisa memakai wheel PyPI normal (pydantic-core, cryptography, dll.) |

### Kenapa akhirnya proot

Eksperimen relokasi prefix Termux berhasil untuk Python murni:

- Binary Python 3.14 Termux jalan dari folder privat asal `LD_LIBRARY_PATH` + `PYTHONHOME`/`PYTHONPATH` di-set.
- Hasil uji: `HELLO_PY 3.14.10 <prefix relokasi>`.

Tapi Hermes butuh `pydantic-core`, `cryptography`, `Pillow`, dan `psutil` dalam bentuk wheel native.
Wheel PyPI dibangun untuk glibc (manylinux), bukan bionic/Android. Termux tidak menyediakan
`python-pydantic`/`python-pydantic-core`. Jadi relokasi prefix **tidak cukup**.

proot dipilih karena:

- Binary proot terbukti bisa direlokasi: cuma butuh `PROOT_LOADER`, `PROOT_TMP_DIR`, dan `LD_LIBRARY_PATH`.
- rootfs Ubuntu memberi glibc + Python 3.12 + wheel manylinux yang sudah teruji.
- Tidak perlu Termux terpasang; semua berada di storage privat aplikasi.
- GPLv2 proot sudah disetujui user untuk dipakai dengan notice.

## 2. Arsitektur

```
┌──────────────────────────────────────────────────────┐
│ APK (com.hermesagent.hermes_android)                 │
│                                                      │
│  Flutter / Ares                                      │
│    └─ LocalEngineClient (MethodChannel + EventChannel)│
│         │                                            │
│         ▼                                            │
│  Kotlin HermesEngineController                       │
│    ├─ downloader + verifikasi SHA-256                │
│    ├─ extractor tar.gz → files/hermes-runtime        │
│    ├─ ProcessBuilder → proot → rootfs → launcher     │
│    ├─ log ring buffer                                │
│    ├─ WakeLock                                       │
│    └─ Foreground service (notifikasi + stop)         │
│                                                      │
│  Storage privat:                                     │
│    files/hermes-runtime/  (prefix + wheel + venv)    │
│    files/hermes-data/     (~/.hermes, .env, session) │
│    files/hermes-engine.log                           │
└──────────────────────────────────────────────────────┘
                │ loopback 127.0.0.1:8642
                ▼
        Ares chat → /v1/chat/completions
```

### Alur pertama kali

1. User buka **+ → Hermes Lokal → Kelola Mesin**.
2. Aplikasi unduh `runtime-manifest.json` (asset bawaan) → URL bundle + SHA-256.
3. Unduh `hermes-runtime-arm64-v8a.tar.gz` ke `cache/` dengan progress.
4. Verifikasi SHA-256. Gagal → hapus, laporkan, jangan ekstrak.
5. Ekstrak ke `files/hermes-runtime` (atomic: ekstrak ke `.tmp`, rename saat sukses).
6. Generate `API_SERVER_KEY` acak (32 byte hex) → simpan di `files/hermes-data/.env`.
7. Tulis marker `.ready` berisi versi bundle.
8. Start gateway lewat `proot -R <rootfs> -b <data>:/data /usr/local/bin/hermes-start.sh`.
   Launcher di dalam rootfs men-set:
   - `HOME`, `HERMES_HOME` → `/data`
   - `PYTHONUNBUFFERED=1`
   - `API_SERVER_ENABLED=true`, `API_SERVER_HOST=127.0.0.1`, `API_SERVER_PORT=8642`
   - `API_SERVER_KEY=<generated>`
   Di luar proot, controller men-set `PROOT_LOADER`, `PROOT_TMP_DIR`, `LD_LIBRARY_PATH`.
9. Ares membuat koneksi lokal otomatis dengan host `127.0.0.1`, port `8642`, API key hasil generate.

### State machine

```
ABSENT → DOWNLOADING → EXTRACTING → CONFIGURING → READY
                                                    │
                                                    ▼
                                                 RUNNING ⇄ STOPPING
                                                    │
                                                  ERROR
```

Setiap transisi dipancarkan lewat EventChannel ke UI.

## 3. MVP — ruang lingkup

### Termasuk
- Foreground service + notifikasi (start/stop dari notifikasi).
- Downloader dengan progress + verifikasi checksum + retry.
- Extractor tar.gz aman (tolak path `..`, tolak symlink absolute).
- Process supervisor: start, stop, detect crash, tail log 200 baris terakhir.
- Generated API key, tidak pernah dikirim ke server kita.
- UI: status, progress, tombol Siapkan / Mulai / Setop, salin API key, lihat log.
- Auto-fill koneksi lokal di Ares.
- Workflow CI build APK + analyze + test.

### Tidak termasuk (phase 2)
- Update engine otomatis dari dalam aplikasi.
- Bundel runtime di dalam APK (opsi 2, ~2 GB).
- Dukungan x86_64 (MVP arm64-v8a dulu).
- OAuth Nous Portal dari dalam UI (masih lewat `hermes setup` bawaan/API key manual).
- proot fallback.

## 4. Bundle runtime

Bundle adalah `tar.gz` berisi:

```
runtime/
  bin/proot                  # dari paket Termux proot
  lib/libtalloc.so.2, libandroid-shmem.so
  libexec/proot/loader, loader32
  rootfs/                    # Ubuntu base arm64 + Python 3.12 + Node + Hermes
    usr/local/bin/hermes-start.sh
    opt/hermes/hermes-agent/ # source/venv hermes
  bundle.json                # versi, hermes_version, python_version
```

Script pembuat: `scripts/build-runtime-bundle.sh` (dijalankan di Termux dengan
`proot-distro ubuntu` terpasang). Hash hasil build masuk
`assets/hermes/runtime-manifest.json`.

Hermes di-pin ke versi yang kompatibel dengan Python 3.12 Ubuntu (MVP: `0.19.0`).

## 5. Keamanan

- Gateway bind `127.0.0.1` saja; tidak diekspos ke LAN.
- `API_SERVER_KEY` generated lokal, disimpan di storage privat, dipakai Ares sebagai Bearer token.
- Tidak ada telemetri dari engine ke server kita.
- File `.env` dan session disimpan di `files/hermes-data`, tidak di external storage.
- `allowBackup=false` sudah aktif di manifest.
- Verifikasi SHA-256 wajib sebelum ekstrak.
- Ekstrak menolak entry dengan `..` atau symlink absolut.

## 6. Risiko & mitigasi

| Risiko | Mitigasi |
|---|---|
| Android mematikan child process | Foreground service + WakeLock + `startForeground` |
| OEM memblokir FGS | Notifikasi + retry saat `onResume`; status tetap terlihat di UI |
| Native wheel PyPI tidak cocok untuk Android | Ambil wheel native dari paket Termux (`python-cryptography`, `python-pillow`, `python-psutil`), sisanya pure-Python dari PyPI |
| Ukuran bundle besar | Download progress, resume tidak wajib di MVP, guard ruang kosong |
| Hermes berubah API | Pin versi wheel di manifest; update lewat bundle baru |
| Lisensi GPL/LGPL | Sertakan NOTICE + source offer untuk komponen yang dipakai |

## 7. Lisensi

- Hermes Agent: MIT.
- Python: PSF License.
- Termux packages: lisensi per paket (kebanyakan MIT/BSD/GPL) — lihat `third_party/NOTICE` yang akan dihasilkan script bundle.
- Node.js: MIT.
- Ares (basis UI): mengikuti lisensi repo upstream.

## 8. Task list MVP

1. [x] Riset kelayakan relokasi Python & proot.
2. [x] Dokumen desain ini.
3. [x] Kotlin: `HermesEngine.kt` (pure logic), `HermesEngineController.kt`, `HermesEngineService.kt`, `HermesEngineChannel.kt`.
4. [x] MainActivity: daftarkan channel + service.
5. [x] Manifest: izin service + notifikasi.
6. [x] Dart: `core/local_engine.dart` + integrasi UI `Hermes Lokal`.
7. [x] Test: Dart + Kotlin pure logic.
8. [x] Script build bundle + manifest asset.
9. [x] Update `docs/HERMES_LOKAL_ID.md`.
10. [ ] Push + jalankan workflow build APK; verifikasi analyze/test/artifact.
11. [ ] Build & upload bundle runtime ke GitHub Release; isi manifest asli.

## 9. Kriteria terima MVP

- `flutter analyze --fatal-infos` hijau di CI.
- `flutter test --no-pub` hijau.
- APK Release terbit dengan service terdaftar.
- Di perangkat arm64: tombol **Siapkan** selesai, **Mulai** hidup, `/health` di `127.0.0.1:8642` balas `ok`, dan Ares bisa chat memakai API key generated.
- Mematikan aplikasi tidak mematikan engine sampai tombol **Setop** ditekan atau notifikasi dihapus.
