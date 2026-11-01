#!/usr/bin/env bash
# Remove only bot-installed protect/guard changes. Panels, databases, Wings,
# Agent, Cloudflare, Docker and user data are intentionally preserved.
set -Eeuo pipefail
TS=$(date -u +%Y%m%d-%H%M%S)
changed=0

restore_reviactyl() {
  local panel=/var/www/reviactyl admin server backup
  test -d "$panel" || return 0
  admin="$panel/app/Http/Middleware/AdminAuthenticate.php"
  server="$panel/app/Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php"
  if test -f "$admin.bak-scoped"; then
    cp "$admin" "$admin.uninstall-protect.$TS.bak" 2>/dev/null || true
    cp "$admin.bak-scoped" "$admin"; echo "[UNINSTALL] Reviactyl AdminAuthenticate dipulihkan."; changed=1
  fi
  backup=$(find /root/reviactyl-scoped-guard-* -maxdepth 1 -type f -name AuthenticateServerAccess.php 2>/dev/null | sort | head -n1 || true)
  if test -n "$backup" && test -f "$server"; then
    cp "$server" "$server.uninstall-protect.$TS.bak"
    cp "$backup" "$server"; echo "[UNINSTALL] Reviactyl server access guard dipulihkan."; changed=1
  fi
  # Guard Manager (halaman web Filament): cabut Page, view, skrip + config
  # manager, dan sudoers www-data-nya.
  if test -f "$panel/app/Filament/Pages/GuardManager.php" || test -f /etc/sudoers.d/reviactyl-guard; then
    rm -f "$panel/app/Filament/Pages/GuardManager.php"
    rm -f "$panel/resources/views/filament/pages/guard-manager.blade.php"
    rm -rf "$panel/storage/app/guard-scripts"
    rm -f "$panel/storage/app/guard-config.json"
    rm -f /etc/sudoers.d/reviactyl-guard
    echo "[UNINSTALL] Guard Manager Reviactyl + sudoers dicabut."; changed=1
  fi
  if [[ $changed -eq 1 ]]; then
    (cd "$panel" && php artisan optimize:clear) || true
    systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php8.2-fpm 2>/dev/null || true
    systemctl restart nginx reviq 2>/dev/null || true
  fi
}

restore_pterodactyl() {
  local panel=/var/www/pterodactyl file backup restored=0
  test -d "$panel" || return 0
  echo "[UNINSTALL] Memindai backup protect Pterodactyl..."
  # Protect Manager (dipasang penuh sejak 2026-11-01): cabut file ciptaannya
  # lebih dulu agar loop pemulihan di bawah tidak memprosesnya, lalu data
  # manager dan sudoers www-data-nya. Route + menu sidebar dipulihkan oleh
  # loop marker di bawah dari backup masing-masing.
  if test -f "$panel/app/Http/Controllers/Admin/ProtectManagerController.php" || test -f "$panel/resources/views/admin/protect-manager.blade.php" || test -f /etc/sudoers.d/pterodactyl-protect; then
    rm -f "$panel/app/Http/Controllers/Admin/ProtectManagerController.php"
    rm -f "$panel/resources/views/admin/protect-manager.blade.php"
    rm -rf "$panel/storage/app/protect-scripts"
    rm -f "$panel/storage/app/protect-config.json"
    rm -f /etc/sudoers.d/pterodactyl-protect
    echo "[UNINSTALL] Protect Manager + config + sudoers www-data dicabut."
    changed=1
  fi
  # Setiap protect script menyimpan salinan sebelum mengubah file. Hanya file
  # yang saat ini masih memiliki marker protect yang dipulihkan, agar kustomisasi
  # panel lain tidak ikut tertimpa.
  while IFS= read -r -d '' file; do
    if ! grep -qEi 'PROTEKSI_JHONALEY|JHONALEY_MASTER|WELCOME_JHONALEY|BRANDING_JHONALEY|jhonaley-footer|jhonaley-welcome' "$file"; then
      continue
    fi
    backup=$(find "$(dirname "$file")" -maxdepth 1 -type f -name "$(basename "$file").bak_*" 2>/dev/null | sort | head -n1 || true)
    if test -n "$backup"; then
      cp "$file" "$file.uninstall-protect.$TS.bak"
      cp "$backup" "$file"
      echo "[UNINSTALL] Dipulihkan: ${file#$panel/}"
      restored=1; changed=1
    else
      echo "[UNINSTALL_WARN] Marker protect ditemukan tanpa backup: ${file#$panel/}"
    fi
  done < <(find "$panel/app" "$panel/resources" "$panel/routes" -type f \( -name '*.php' -o -name '*.blade.php' -o -name '*.js' \) -print0 2>/dev/null)

  # Files created solely by the protect scripts can be safely removed.
  rm -f "$panel/app/Http/Middleware/ProtectAdminUser.php"
  if test -f "$panel/app/Http/Kernel.php"; then
    sed -i.bak-uninstall-protect '/ProtectAdminUser::class/d' "$panel/app/Http/Kernel.php"
    rm -f "$panel/app/Http/Kernel.php.bak-uninstall-protect"
  fi
  if [[ $restored -eq 1 ]]; then
    (cd "$panel" && php artisan optimize:clear && php artisan view:clear && php artisan route:clear && php artisan config:clear)
  fi
  systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php8.2-fpm 2>/dev/null || true
  systemctl restart nginx pteroq 2>/dev/null || true
}

restore_reviactyl
restore_pterodactyl
if [[ $changed -eq 0 ]]; then
  echo "[UNINSTALL] Tidak menemukan protect/guard bot yang dapat dipulihkan. Panel tidak diubah."
else
  echo "[UNINSTALL_OK] Protect/guard yang terdeteksi sudah dilepas. Backup sebelum uninstall diberi suffix .uninstall-protect.$TS.bak"
fi
