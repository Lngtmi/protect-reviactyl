# Protect Reviactyl — Scoped Admin Guard

Script protect untuk **Reviactyl Panel**: membatasi admin selain owner hanya bisa mengakses server miliknya sendiri, lengkap dengan halaman 403/404 khusus yang teksnya bisa diatur.

Satu file, dijalankan langsung di VPS tempat panel Reviactyl terinstall:

```
install-scoped-admin-guard.sh
```

## Kebutuhan

- Panel **Reviactyl sudah terinstall** di `/var/www/reviactyl`
- Dijalankan sebagai **root** di VPS panel
- PHP 8.3 FPM + MariaDB (sesuai instalasi Reviactyl standar)

## Cara pakai

```bash
sudo bash install-scoped-admin-guard.sh
```

Dengan teks halaman & owner kustom:

```bash
sudo OWNER_ID=1 \
  GUARD_TITLE='AKSES DIBATASI' \
  GUARD_OWNER_MESSAGE='Menu ini hanya dapat diakses Owner.' \
  GUARD_SERVER_MESSAGE='Server ini bukan milik Anda.' \
  bash install-scoped-admin-guard.sh
```

| Variable | Default | Keterangan |
| --- | --- | --- |
| `OWNER_ID` | `1` | ID user owner di panel |
| `GUARD_TITLE` | `AKSES DIBATASI` | Judul halaman 403 (maks 80 karakter) |
| `GUARD_OWNER_MESSAGE` | `Menu ini hanya dapat diakses Owner.` | Pesan 403 (maks 240 karakter) |
| `GUARD_SERVER_MESSAGE` | `Server ini bukan milik Anda.` | Pesan server bukan milik user (maks 240 karakter) |
| `GUARD_403_BUTTON` | `Kembali ke Dashboard` | Teks tombol 403 (maks 80 karakter) |
| `GUARD_404_TITLE` | mengikuti `GUARD_TITLE` | Judul halaman 404 (maks 80 karakter) |
| `GUARD_404_BUTTON` | `Kembali ke Dashboard` | Teks tombol 404 (maks 80 karakter) |

## Keamanan

- Semua file yang diubah **dibackup dulu** ke `/root/reviactyl-scoped-guard-<tanggal-jam>/` di VPS.
- Script berhenti dengan error jelas bila panel tidak ditemukan, owner tidak ada di database, atau teks melebihi batas — sebelum mengubah apa pun.
- Script ini **tidak** menambah akses sudo untuk web server dan tidak mengubah database, Wings/Agent, atau data server.

## Kontak

Ada pertanyaan atau butuh bantuan? Hubungi saya di Telegram: [@pratamanie](https://t.me/pratamanie)

---
SOURCE CODE BY PRATAMA
