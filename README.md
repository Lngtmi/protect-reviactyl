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

## Cara Install — Bash (1 perintah)

Ini satu-satunya cara install yang disarankan. Tidak perlu download apa pun — jalankan di VPS panel sebagai root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Lngtmi/protect-reviactyl/main/install-scoped-admin-guard.sh)
```

Script langsung berjalan dan memasang Guard + Guard Manager. Secara bawaan **Owner adalah user dengan ID 1** di panel, dan teks halaman blokir memakai teks standar Guard — keduanya bisa diubah belakangan dari halaman Guard Manager di panel.

## Cara Uninstall

Guard dari repo ini dilepas memakai script terpisah: **[uninstall-all-protect](https://github.com/Lngtmi/uninstall-all-protect)** — panel dan data server tetap utuh, hanya protect/guard-nya yang dicabut.

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
