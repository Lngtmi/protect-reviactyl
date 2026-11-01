# Protect Reviactyl — Scoped Admin Guard

Script protect untuk **Reviactyl Panel**: membatasi admin selain owner hanya bisa mengakses server miliknya sendiri dan memblokir menu-menu admin khusus owner (Nodes, Locations, Databases, Settings, API, Nests, Users, Roles, Alerts, Webhooks, Activity Log, Designify, Monitoring, Software Updates, dll), lengkap dengan halaman 403/404 khusus yang teksnya bisa diatur.

Versi ini juga memasang **Guard Manager**: halaman khusus Owner di panel (menu sidebar) untuk mengubah teks Guard, lalu menerapkan (**Simpan**) atau melepas (**Lepas Guard**) proteksi langsung dari web — tanpa perlu menjalankan script lagi.

Satu file, dijalankan langsung di VPS tempat panel Reviactyl terinstall:

```
install-scoped-admin-guard.sh
```

## Kebutuhan

- Panel **Reviactyl sudah terinstall** di `/var/www/reviactyl`
- Dijalankan sebagai **root** di VPS panel
- PHP 8.3 FPM + MariaDB (sesuai instalasi Reviactyl standar)

## Cara Install — Pilih 2 Model

### Model 1 — Bash (1 perintah, langsung jalan dari GitHub)

Tidak perlu download apa pun. Jalankan di VPS panel sebagai root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Lngtmi/protect-reviactyl/main/install-scoped-admin-guard.sh)
```

Dengan teks halaman & owner kustom:

```bash
OWNER_ID=1 GUARD_TITLE='AKSES DIBATASI' GUARD_OWNER_MESSAGE='Menu ini hanya dapat diakses Owner.' \
  bash <(curl -fsSL https://raw.githubusercontent.com/Lngtmi/protect-reviactyl/main/install-scoped-admin-guard.sh)
```

### Model 2 — Source Code (download / clone dulu)

```bash
git clone https://github.com/Lngtmi/protect-reviactyl.git
cd protect-reviactyl
sudo bash install-scoped-admin-guard.sh
```

Atau unduh ZIP dari tombol **Code → Download ZIP** di halaman repo ini, ekstrak, lalu jalankan `sudo bash install-scoped-admin-guard.sh`.

### Variabel

| Variable | Default | Keterangan |
| --- | --- | --- |
| `OWNER_ID` | `1` | ID user owner di panel |
| `GUARD_TITLE` | `AKSES DIBATASI` | Judul halaman 403 (maks 80 karakter) |
| `GUARD_OWNER_MESSAGE` | `Menu ini hanya dapat diakses Owner.` | Pesan 403 (maks 240 karakter) |
| `GUARD_SERVER_MESSAGE` | `Server ini bukan milik Anda.` | Pesan server bukan milik user (maks 240 karakter) |
| `GUARD_403_BUTTON` | `Kembali ke Dashboard` | Teks tombol 403 (maks 80 karakter) |
| `GUARD_404_TITLE` | mengikuti `GUARD_TITLE` | Judul halaman 404 (maks 80 karakter) |
| `GUARD_404_BUTTON` | `Kembali ke Dashboard` | Teks tombol 404 (maks 80 karakter) |

## Cara Uninstall (melepas Guard / Protect)

Pakai script pendamping `uninstall-all-protect.sh` — memulihkan file panel dari backup dan mencabut Guard Manager beserta sudoers-nya. Panel, database, Wings/Agent, dan data server **tidak** dihapus.

### Model 1 — Bash (1 perintah)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Lngtmi/protect-reviactyl/main/uninstall-all-protect.sh)
```

### Model 2 — Source Code

```bash
sudo bash uninstall-all-protect.sh
```

> Sesuai namanya, script ini melepas **semua** protect yang terdeteksi di VPS: Guard Reviactyl (repo ini) dan juga Protect Pterodactyl bila ada di VPS yang sama. Bila tidak ada protect yang terdeteksi, script berhenti tanpa mengubah apa pun.

## Cara kerja Guard Manager

- Semua nilai Guard disimpan di satu file config panel: `storage/app/guard-config.json` — halaman web dan script membaca sumber yang sama.
- Halaman Guard Manager hanya muncul untuk **Owner** (user ID sesuai `OWNER_ID`).
- Tombol di halaman web menjalankan script apply/remove resmi di `storage/app/guard-scripts/` melalui sudo yang **dibatasi hanya untuk script-script tersebut** (`/etc/sudoers.d/reviactyl-guard`) — bukan akses root bebas untuk web server.
- Status Terinstall / Belum Terinstall dibaca dari marker Guard di file middleware panel yang aktif.

## Keamanan

- Semua file yang diubah **dibackup dulu** secara scoped (`.bak-scoped`) sebelum Guard diterapkan; melepas Guard memulihkan file asli dari backup tersebut.
- Script berhenti dengan error jelas bila panel tidak ditemukan, owner tidak ada di database, atau teks melebihi batas — sebelum mengubah apa pun.
- Script ini tidak mengubah database panel, Wings/Agent, atau data server.

## Kontak

Ada pertanyaan atau butuh bantuan? Hubungi saya di Telegram: [@pratamanie](https://t.me/pratamanie)

---
SOURCE CODE BY PRATAMA
