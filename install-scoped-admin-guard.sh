#!/usr/bin/env bash
# Pasang Guard Reviactyl + Guard Manager (halaman web Filament, khusus Owner).
# Bot menjalankan file ini via SSH sebagai root dengan env GUARD_* dari wizard.
# File ini menulis guard-config.json, skrip apply/remove di storage panel,
# halaman GuardManager, dan sudoers terbatas untuk www-data; lalu menerapkan
# Guard lewat skrip apply yang sama dengan yang dipakai halaman web.
set -Eeuo pipefail
P=/var/www/reviactyl
GUARD_TITLE=${GUARD_TITLE:-'AKSES DIBATASI'}
GUARD_OWNER_MESSAGE=${GUARD_OWNER_MESSAGE:-'Menu ini hanya dapat diakses Owner.'}
GUARD_SERVER_MESSAGE=${GUARD_SERVER_MESSAGE:-'Server ini bukan milik Anda.'}
GUARD_403_BUTTON=${GUARD_403_BUTTON:-'Kembali ke Dashboard'}
GUARD_404_TITLE=${GUARD_404_TITLE:-"$GUARD_TITLE"}
GUARD_404_BUTTON=${GUARD_404_BUTTON:-'Kembali ke Dashboard'}
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
[[ ${#GUARD_TITLE} -le 80 && ${#GUARD_404_TITLE} -le 80 && ${#GUARD_OWNER_MESSAGE} -le 240 && ${#GUARD_SERVER_MESSAGE} -le 240 && ${#GUARD_403_BUTTON} -le 80 && ${#GUARD_404_BUTTON} -le 80 ]] || { echo 'Teks Guard terlalu panjang.' >&2; exit 1; }
O=${OWNER_ID:-1}
cd "$P"
mariadb panel -Nse "SELECT id FROM users WHERE id=$O" | grep -qx "$O" || { echo 'Owner not found'; exit 1; }
export GUARD_TITLE GUARD_OWNER_MESSAGE GUARD_SERVER_MESSAGE GUARD_403_BUTTON GUARD_404_TITLE GUARD_404_BUTTON OWNER_ID="$O"

CFG="$P/storage/app/guard-config.json"
SCRIPTS_DIR="$P/storage/app/guard-scripts"
mkdir -p "$SCRIPTS_DIR"

# --- Config: satu-satunya sumber nilai Guard (bot + web membaca ini) ---
python3 - "$CFG" <<'PY'
import json, os, sys
cfg = {
    "owner_id": int(os.environ["OWNER_ID"]),
    "guard_title": os.environ["GUARD_TITLE"],
    "guard_owner_message": os.environ["GUARD_OWNER_MESSAGE"],
    "guard_server_message": os.environ["GUARD_SERVER_MESSAGE"],
    "guard_403_button": os.environ["GUARD_403_BUTTON"],
    "guard_404_title": os.environ["GUARD_404_TITLE"],
    "guard_404_button": os.environ["GUARD_404_BUTTON"],
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, ensure_ascii=False, indent=4)
print("Guard config ditulis.")
PY
chown www-data:www-data "$CFG" 2>/dev/null || true
chmod 664 "$CFG" 2>/dev/null || true

# --- Skrip apply: mesin Guard (dipakai bot di bawah + halaman web via sudo) ---
cat > "$SCRIPTS_DIR/guard-apply.sh" <<'APPLY_SH'
#!/usr/bin/env bash
# Guard Manager apply: menerapkan Guard Reviactyl dari guard-config.json.
# Dijalankan sebagai root (bot via SSH, atau www-data via sudo dari halaman
# Guard Manager). Tidak menerima argumen.
set -Eeuo pipefail
P=/var/www/reviactyl
A=$P/app/Http/Middleware/AdminAuthenticate.php
S=$P/app/Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php
W=$P/resources/views/templates/wrapper.blade.php
CFG=$P/storage/app/guard-config.json
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
[[ -f "$CFG" ]] || { echo "Config tidak ditemukan: $CFG" >&2; exit 1; }
eval "$(python3 - "$CFG" <<'PYEOF'
import json, shlex, sys
cfg = json.load(open(sys.argv[1]))
for cfg_key, env_key in {
    "owner_id": "OWNER_ID",
    "guard_title": "GUARD_TITLE",
    "guard_owner_message": "GUARD_OWNER_MESSAGE",
    "guard_server_message": "GUARD_SERVER_MESSAGE",
    "guard_403_button": "GUARD_403_BUTTON",
    "guard_404_title": "GUARD_404_TITLE",
    "guard_404_button": "GUARD_404_BUTTON",
}.items():
    print(f"export {env_key}={shlex.quote(str(cfg.get(cfg_key, '')))}")
PYEOF
)"
O=${OWNER_ID:-1}
[[ ${#GUARD_TITLE} -le 80 && ${#GUARD_404_TITLE} -le 80 && ${#GUARD_OWNER_MESSAGE} -le 240 && ${#GUARD_SERVER_MESSAGE} -le 240 && ${#GUARD_403_BUTTON} -le 80 && ${#GUARD_404_BUTTON} -le 80 ]] || { echo 'Teks Guard terlalu panjang.' >&2; exit 1; }
TITLE_PHP=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$GUARD_TITLE")
OWNER_PHP=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$GUARD_OWNER_MESSAGE")
SERVER_PHP=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$GUARD_SERVER_MESSAGE")
export GUARD_TITLE GUARD_OWNER_MESSAGE GUARD_SERVER_MESSAGE GUARD_403_BUTTON GUARD_404_TITLE GUARD_404_BUTTON
cd "$P"
# Backup hanya dibuat sekali, sebelum Guard pertama kali terpasang, agar
# .bak-scoped dan folder backup root selalu berisi versi bawaan panel.
if ! grep -q 'SCOPED_ADMIN_GUARD' "$A" 2>/dev/null; then
  B=/root/reviactyl-scoped-guard-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"; cp "$A" "$S" "$B/"
  [[ -f "$W" ]] && cp "$W" "$B/"
  cp "$A" "$A.bak-scoped"
  echo "Backup dibuat: $B"
fi
# A previously interrupted/older Guard run may have left this middleware with
# invalid PHP. Restore the last known pre-Guard copy before applying this version.
if ! php -l "$S" >/dev/null 2>&1; then
  restored=0
  for candidate in "${S}.bak-scoped" /root/reviactyl-scoped-guard-*/AuthenticateServerAccess.php; do
    [[ -f "$candidate" ]] || continue
    if php -l "$candidate" >/dev/null 2>&1; then
      cp "$candidate" "$S"; restored=1
      echo 'Invalid server middleware restored from local backup.'
      break
    fi
  done
  if [[ $restored -eq 0 ]]; then
    # Final recovery path for an interrupted first run: fetch the unmodified
    # middleware from the official Reviactyl Panel source, then validate it.
    recovery=/tmp/reviactyl-AuthenticateServerAccess.php
    curl -fsSL 'https://raw.githubusercontent.com/reviactyl/panel/develop/app/Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php' -o "$recovery"
    php -l "$recovery" >/dev/null || { echo 'Official recovery middleware failed validation.'; exit 1; }
    cp "$recovery" "$S"; rm -f "$recovery"
    echo 'Invalid server middleware restored from official Reviactyl source.'
  fi
fi
cat >"$A" <<PHP
<?php
// SCOPED_ADMIN_GUARD - dihasilkan Guard Manager; jangan edit manual.
namespace App\Http\Middleware;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
class AdminAuthenticate {
 public function handle(Request \$request, \\Closure \$next): mixed {
  \$guardTitle=$TITLE_PHP; \$ownerMessage=$OWNER_PHP; \$serverMessage=$SERVER_PHP;
  \$u=\$request->user(); if (!\$u || !\$u->root_admin) throw new AccessDeniedHttpException();
  if ((int)\$u->id === $O) return \$next(\$request);
  \$p='/'.ltrim(\$request->path(),'/');
  foreach(['/admin/nodes','/admin/locations','/admin/databases','/admin/database-host','/admin/settings','/admin/api','/admin/application-api','/admin/extensions','/admin/mounts','/admin/nests','/admin/users','/admin/roles','/admin/alerts','/admin/webhooks','/admin/activity-log','/admin/designify','/admin/monitoring','/admin/software-updates'] as \$b) if (\$p===\$b || str_starts_with(\$p,\$b.'/')) throw new AccessDeniedHttpException(\$guardTitle . ': ' . \$ownerMessage);
  if (preg_match('#^/admin/users/(?:users/)?([0-9]+)(?:/|$)#', \$p, \$m)) { \$target=\\App\\Models\\User::find((int)\$m[1]); if (!\$target || (int)\$target->id !== (int)\$u->id) throw new AccessDeniedHttpException(\$guardTitle . ': ' . \$ownerMessage); }
  if (\$p==='/admin/servers/create' || \$p==='/admin/servers/servers/create') throw new AccessDeniedHttpException(\$guardTitle . ': ' . \$ownerMessage);
  if (preg_match('#^/admin/servers/(?:servers/)?([0-9]+)(?:/|$)#', \$p, \$m)) { \$target=\\App\\Models\\Server::find((int)\$m[1]); if (!\$target || (int)\$target->owner_id !== (int)\$u->id) throw new AccessDeniedHttpException(\$guardTitle . ': ' . \$serverMessage); }
  return \$next(\$request);
 }
}
PHP
php -l "$A"
python3 - "$S" "$O" <<'PYEOF'
import json, os, re, sys
p,o=sys.argv[1:]; s=open(p).read()
marker='SCOPED_ADMIN_GUARD: non-owner root admin only accesses own servers.'
server_message=json.dumps(os.environ['GUARD_SERVER_MESSAGE'], ensure_ascii=False)
if marker in s:
    # Keep an existing Guard installation updatable: older editions returned
    # Reviactyl's stock API message, causing the React server page to ignore
    # the message entered in the bot.
    start=s.find('throw new NotFoundHttpException(', s.find(marker))
    if start < 0:
        raise SystemExit('existing server guard is incomplete; no server file changed')
    end=s.find(';', start)
    if end < 0:
        raise SystemExit('existing server guard is invalid; no server file changed')
    s=s[:start] + 'throw new NotFoundHttpException(' + server_message + ');' + s[end + 1:]
    open(p,'w').write(s)
    print('Server guard message updated.')
    sys.exit(0)
# Reviactyl v26 no longer has the old preview condition used by the first script.
# Inject before its normal owner/subuser/root-admin access check, so normal
# subusers keep working while non-owner root admins cannot view others' servers.
anchor=r"(\n\s*// At the very least, ensure that the user trying to make this request is the\n\s*// server owner, a subuser, or a root admin\. We'll leave it up to the controllers\n\s*// to authenticate more detailed permissions if needed\.\n)"
guard=("\n        // SCOPED_ADMIN_GUARD: non-owner root admin only accesses own servers.\n"
       "        if ($user->root_admin && (int) $user->id !== %s && (int) $server->owner_id !== (int) $user->id) {\n"
       "            throw new NotFoundHttpException(%s);\n"
       "        }\n" % (o, server_message))
s,n=re.subn(anchor,lambda m:m.group(1)+guard,s,count=1)
if n != 1:
    raise SystemExit('server access anchor not found; no server file changed')
open(p,'w').write(s)
PYEOF
php -l "$S"
# The server page is React and its error card has no return button by default.
# Install a small DOM adapter in Blade instead of rewriting hashed JS assets.
# It reads the same Designify 404 settings saved below, so all three values
# entered for "server user lain" (title, message, button) appear together.
python3 - "$W" <<'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit('Panel wrapper view tidak ditemukan; Guard dihentikan agar panel tidak setengah berubah.')
text = path.read_text(encoding='utf-8')
start = '<!-- SCOPED_ADMIN_GUARD_REACT_START -->'
end = '<!-- SCOPED_ADMIN_GUARD_REACT_END -->'
if start in text:
    before, remainder = text.split(start, 1)
    _, after = remainder.split(end, 1)
    text = before + after

block = r'''
<!-- SCOPED_ADMIN_GUARD_REACT_START -->
<script>
(() => {
    const applyServerGuardText = () => {
        if (!location.pathname.startsWith('/server/')) return;
        const error = window.PanelConfiguration?.errors?.['404'];
        if (!error?.title || !error?.message || !error?.button) return;

        for (const heading of document.querySelectorAll('h2')) {
            const container = heading.parentElement;
            const message = container?.querySelector('p');
            if (!message) continue;
            const shown = message.textContent?.trim() || '';
            const isGuardError = shown === error.message || shown === 'The requested resource does not exist on this server.';
            if (!isGuardError) continue;

            const card = heading.closest('.relative');
            // The observer also sees the DOM changes made below. Check the
            // marker first so it cannot endlessly rewrite the card and keep
            // the panel's loading indicator active.
            if (!card || card.querySelector('[data-scoped-guard-return]')) continue;
            heading.textContent = error.title;
            message.textContent = error.message;
            const link = document.createElement('a');
            link.href = '/';
            link.dataset.scopedGuardReturn = 'true';
            link.textContent = error.button;
            link.className = 'mt-6 inline-flex rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500';
            card.appendChild(link);
        }
    };
    new MutationObserver(applyServerGuardText).observe(document.documentElement, { childList: true, subtree: true });
    addEventListener('load', applyServerGuardText);
    applyServerGuardText();
})();
</script>
<!-- SCOPED_ADMIN_GUARD_REACT_END -->
'''
if '</head>' not in text:
    raise SystemExit('Tag </head> tidak ditemukan pada wrapper panel.')
path.write_text(text.replace('</head>', block + '\n</head>', 1), encoding='utf-8')
print('React Guard adapter installed.')
PYEOF
# Designify owns the visible 403/404 pages. Persist every configurable text
# through its SettingsRepository so the page shown to users matches Guard.
php artisan tinker --execute='
$repo = app(\App\Contracts\Repository\SettingsRepositoryInterface::class);
$map = [
 "settings::designify:errors:403:title" => getenv("GUARD_TITLE"),
 "settings::designify:errors:403:message" => getenv("GUARD_OWNER_MESSAGE"),
 "settings::designify:errors:403:button" => getenv("GUARD_403_BUTTON"),
 "settings::designify:errors:404:title" => getenv("GUARD_404_TITLE"),
 "settings::designify:errors:404:message" => getenv("GUARD_SERVER_MESSAGE"),
 "settings::designify:errors:404:button" => getenv("GUARD_404_BUTTON"),
];
foreach ($map as $key => $value) { $repo->set($key, $value); }
' --no-interaction
php artisan optimize:clear
# Jadwalkan restart php-fpm secara detach: aman dipanggil dari halaman web
# (request yang sedang berjalan tidak ikut terputus).
( setsid bash -c 'sleep 2; systemctl restart php8.3-fpm' >/dev/null 2>&1 & ) || true
echo "Guard diterapkan. Owner ID: $O"
APPLY_SH

# --- Skrip remove: memulihkan middleware bawaan dari backup ---
cat > "$SCRIPTS_DIR/guard-remove.sh" <<'REMOVE_SH'
#!/usr/bin/env bash
# Guard Manager remove: melepas Guard Reviactyl (pulihkan file bawaan panel
# dari backup yang dibuat guard-apply). Config teks TIDAK dihapus, jadi Guard
# bisa dipasang lagi dari halaman Guard Manager kapan saja.
set -Eeuo pipefail
P=/var/www/reviactyl
A=$P/app/Http/Middleware/AdminAuthenticate.php
S=$P/app/Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php
W=$P/resources/views/templates/wrapper.blade.php
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
cd "$P"
FIRST_BAK=$(ls -d /root/reviactyl-scoped-guard-*/ 2>/dev/null | sort | head -n1 || true)
if [[ -f "$A.bak-scoped" ]]; then
  cp "$A.bak-scoped" "$A"; echo 'AdminAuthenticate dipulihkan dari .bak-scoped.'
elif [[ -n "$FIRST_BAK" && -f "${FIRST_BAK}AdminAuthenticate.php" ]]; then
  cp "${FIRST_BAK}AdminAuthenticate.php" "$A"; echo 'AdminAuthenticate dipulihkan dari backup root.'
else
  echo 'Backup AdminAuthenticate tidak ditemukan; file dibiarkan.' >&2
fi
if [[ -n "$FIRST_BAK" && -f "${FIRST_BAK}AuthenticateServerAccess.php" ]]; then
  cp "${FIRST_BAK}AuthenticateServerAccess.php" "$S"; echo 'AuthenticateServerAccess dipulihkan dari backup root.'
else
  python3 - "$S" <<'PYEOF'
import sys
lines = open(sys.argv[1]).read().splitlines(keepends=True)
out = []
i = 0
removed = 0
while i < len(lines):
    if 'SCOPED_ADMIN_GUARD: non-owner root admin only accesses own servers.' in lines[i]:
        i += 4  # komentar marker + if { + throw + }
        removed += 1
        continue
    out.append(lines[i])
    i += 1
open(sys.argv[1], 'w').write(''.join(out))
print(f'Blok server guard dicabut dari middleware ({removed} blok).')
PYEOF
fi
python3 - "$W" <<'PYEOF'
import sys
from pathlib import Path
path = Path(sys.argv[1])
if path.is_file():
    text = path.read_text(encoding='utf-8')
    start = '<!-- SCOPED_ADMIN_GUARD_REACT_START -->'
    end = '<!-- SCOPED_ADMIN_GUARD_REACT_END -->'
    if start in text and end in text:
        before, remainder = text.split(start, 1)
        _, after = remainder.split(end, 1)
        path.write_text(before + after, encoding='utf-8')
        print('React Guard adapter dilepas.')
PYEOF
php artisan optimize:clear
( setsid bash -c 'sleep 2; systemctl restart php8.3-fpm' >/dev/null 2>&1 & ) || true
echo 'Guard dilepas.'
REMOVE_SH

chmod 755 "$SCRIPTS_DIR/guard-apply.sh" "$SCRIPTS_DIR/guard-remove.sh"
chown root:root "$SCRIPTS_DIR" "$SCRIPTS_DIR/guard-apply.sh" "$SCRIPTS_DIR/guard-remove.sh" 2>/dev/null || true

# --- Halaman Guard Manager (Filament Page, otomatis tampil di sidebar admin) ---
mkdir -p "$P/app/Filament/Pages" "$P/resources/views/filament/pages"
cat > "$P/app/Filament/Pages/GuardManager.php" <<'PAGE_PHP'
<?php

namespace App\Filament\Pages;

use Filament\Actions\Action;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Concerns\InteractsWithForms;
use Filament\Notifications\Notification;
use Filament\Pages\Concerns\InteractsWithHeaderActions;
use Filament\Pages\Page;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Contracts\HasSchemas;

class GuardManager extends Page implements HasSchemas
{
    use InteractsWithForms;
    use InteractsWithHeaderActions;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-shield';

    protected static ?string $navigationLabel = 'Guard Manager';

    protected static ?int $navigationSort = 99;

    protected string $view = 'filament.pages.guard-manager';

    public ?array $data = [];

    public static function configPath(): string
    {
        return storage_path('app/guard-config.json');
    }

    public static function guardConfig(): array
    {
        $defaults = [
            'owner_id' => 1,
            'guard_title' => 'AKSES DIBATASI',
            'guard_owner_message' => 'Menu ini hanya dapat diakses Owner.',
            'guard_server_message' => 'Server ini bukan milik Anda.',
            'guard_403_button' => 'Kembali ke Dashboard',
            'guard_404_title' => 'AKSES DIBATASI',
            'guard_404_button' => 'Kembali ke Dashboard',
        ];
        $path = static::configPath();
        if (is_file($path)) {
            $decoded = json_decode((string) file_get_contents($path), true);
            if (is_array($decoded)) {
                $defaults = array_merge($defaults, $decoded);
            }
        }

        return $defaults;
    }

    public static function canAccess(): bool
    {
        $user = auth()->user();
        if (! $user || ! $user->root_admin) {
            return false;
        }

        return (int) $user->id === (int) static::guardConfig()['owner_id'];
    }

    public static function shouldRegisterNavigation(): bool
    {
        return static::canAccess();
    }

    public function ownerId(): int
    {
        return (int) static::guardConfig()['owner_id'];
    }

    public function guardInstalled(): bool
    {
        // Deteksi murni dari penanda di file aktif: file backup memang sengaja
        // dipertahankan setelah Guard dilepas, jadi keberadaannya tidak boleh
        // dipakai sebagai tanda terpasang.
        $admin = app_path('Http/Middleware/AdminAuthenticate.php');
        if (is_file($admin) && str_contains((string) file_get_contents($admin), 'SCOPED_ADMIN_GUARD')) {
            return true;
        }
        $server = app_path('Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php');

        return is_file($server) && str_contains((string) file_get_contents($server), 'SCOPED_ADMIN_GUARD');
    }

    public function mount(): void
    {
        $cfg = static::guardConfig();
        $this->form->fill([
            'guard_title' => $cfg['guard_title'],
            'guard_owner_message' => $cfg['guard_owner_message'],
            'guard_server_message' => $cfg['guard_server_message'],
            'guard_403_button' => $cfg['guard_403_button'],
            'guard_404_title' => $cfg['guard_404_title'],
            'guard_404_button' => $cfg['guard_404_button'],
        ]);
    }

    protected function getFormStatePath(): ?string
    {
        return 'data';
    }

    protected function getFormSchema(): array
    {
        return [
            Section::make('Teks Guard')
                ->description('Teks yang tampil di halaman 403/404 untuk admin selain Owner.')
                ->schema([
                    TextInput::make('guard_title')->label('Judul Guard (403)')->maxLength(80)->required(),
                    Textarea::make('guard_owner_message')->label('Pesan Akses Admin')->maxLength(240)->rows(2)->required(),
                    TextInput::make('guard_403_button')->label('Tombol 403')->maxLength(80)->required(),
                    TextInput::make('guard_404_title')->label('Judul 404')->maxLength(80)->required(),
                    Textarea::make('guard_server_message')->label('Pesan Akses Server (404)')->maxLength(240)->rows(2)->required(),
                    TextInput::make('guard_404_button')->label('Tombol 404')->maxLength(80)->required(),
                ]),
        ];
    }

    protected function getHeaderActions(): array
    {
        return [
            Action::make('save')
                ->label('Simpan Konfigurasi')
                ->icon('tabler-device-floppy')
                ->action(fn () => $this->save()),
            Action::make('installGuard')
                ->label('Pasang Guard')
                ->icon('tabler-shield-check')
                ->color('success')
                ->visible(fn () => ! $this->guardInstalled())
                ->action(fn () => $this->installGuard()),
            Action::make('uninstallGuard')
                ->label('Lepas Guard')
                ->icon('tabler-shield-x')
                ->color('danger')
                ->requiresConfirmation()
                ->modalHeading('Lepas Guard?')
                ->modalDescription('Middleware panel dikembalikan ke bawaan Reviactyl. Konfigurasi teks tetap disimpan dan Guard bisa dipasang lagi kapan saja.')
                ->visible(fn () => $this->guardInstalled())
                ->action(fn () => $this->uninstallGuard()),
        ];
    }

    public function save(): void
    {
        $this->writeConfigFromForm();
        if ($this->guardInstalled()) {
            $this->launchScript('guard-apply.sh');
            Notification::make()->title('Konfigurasi disimpan, Guard diterapkan ulang.')->success()->send();
        } else {
            Notification::make()->title('Konfigurasi disimpan.')->success()->send();
        }
    }

    public function installGuard(): void
    {
        $this->writeConfigFromForm();
        $this->launchScript('guard-apply.sh');
        Notification::make()->title('Guard sedang dipasang. Muat ulang halaman sebentar lagi.')->success()->send();
    }

    public function uninstallGuard(): void
    {
        $this->launchScript('guard-remove.sh');
        Notification::make()->title('Guard sedang dilepas. Muat ulang halaman sebentar lagi.')->success()->send();
    }

    private function writeConfigFromForm(): void
    {
        $form = $this->getForm('form');
        $state = $form?->getState() ?? [];
        $cfg = static::guardConfig();
        foreach (['guard_title', 'guard_owner_message', 'guard_server_message', 'guard_403_button', 'guard_404_title', 'guard_404_button'] as $key) {
            if (array_key_exists($key, $state)) {
                $cfg[$key] = $state[$key];
            }
        }
        file_put_contents(static::configPath(), json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    private function launchScript(string $script): void
    {
        $path = storage_path('app/guard-scripts/'.$script);
        // Log WAJIB di storage/logs: redirect dibuat oleh shell www-data
        // sebelum sudo berjalan, jadi targetnya harus bisa ditulis www-data.
        // Folder guard-scripts milik root (agar skripnya tidak bisa diganti
        // www-data), sehingga log di sana akan gagal dibuka dan skrip tidak
        // pernah jalan.
        $log = storage_path('logs/guard-manager.log');
        shell_exec('nohup sudo /usr/bin/bash '.escapeshellarg($path).' >> '.escapeshellarg($log).' 2>&1 &');
    }
}
PAGE_PHP
php -l "$P/app/Filament/Pages/GuardManager.php"

cat > "$P/resources/views/filament/pages/guard-manager.blade.php" <<'VIEW_BLADE'
<x-filament-panels::page>
    <div class="rounded-xl bg-white p-4 shadow ring-1 ring-gray-950/5 dark:bg-gray-900 dark:ring-white/10">
        @if ($this->guardInstalled())
            <p class="text-sm text-gray-700 dark:text-gray-200"><span class="font-semibold text-green-600">● Terinstall</span> — Guard aktif: admin selain Owner (ID {{ $this->ownerId() }}) dibatasi dari menu dan server orang lain.</p>
        @else
            <p class="text-sm text-gray-700 dark:text-gray-200"><span class="font-semibold text-red-500">● Belum Terinstall</span> — Guard belum aktif. Atur teksnya di bawah lalu klik Pasang Guard.</p>
        @endif
    </div>
    {{ $this->form }}
</x-filament-panels::page>
VIEW_BLADE

# --- Sudoers: www-data hanya boleh menjalankan dua skrip Guard ini ---
cat > /etc/sudoers.d/reviactyl-guard <<'SUDO_TXT'
# Reviactyl Guard Manager: www-data hanya boleh menjalankan skrip apply/remove
# Guard sebagai root (tanpa argumen; skrip membaca guard-config.json).
www-data ALL=(root) NOPASSWD: /usr/bin/bash /var/www/reviactyl/storage/app/guard-scripts/guard-apply.sh
www-data ALL=(root) NOPASSWD: /usr/bin/bash /var/www/reviactyl/storage/app/guard-scripts/guard-remove.sh
SUDO_TXT
chmod 440 /etc/sudoers.d/reviactyl-guard
if command -v visudo >/dev/null 2>&1; then
  visudo -cf /etc/sudoers.d/reviactyl-guard >/dev/null || { echo 'Sudoers Guard Manager tidak valid; dibatalkan.' >&2; rm -f /etc/sudoers.d/reviactyl-guard; exit 1; }
fi

# --- Terapkan Guard sekarang dari config yang baru ditulis ---
bash "$SCRIPTS_DIR/guard-apply.sh"
php artisan optimize:clear
systemctl restart php8.3-fpm nginx reviq
echo "Installed. Backup dibuat oleh guard-apply bila pertama kali. | Guard Manager: /admin/guard-manager | Guard title: $GUARD_TITLE"
