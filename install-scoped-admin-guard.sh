#!/usr/bin/env bash
set -Eeuo pipefail
P=/var/www/reviactyl
A=$P/app/Http/Middleware/AdminAuthenticate.php
S=$P/app/Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php
W=$P/resources/views/templates/wrapper.blade.php
GUARD_TITLE=${GUARD_TITLE:-'AKSES DIBATASI'}
GUARD_OWNER_MESSAGE=${GUARD_OWNER_MESSAGE:-'Menu ini hanya dapat diakses Owner.'}
GUARD_SERVER_MESSAGE=${GUARD_SERVER_MESSAGE:-'Server ini bukan milik Anda.'}
GUARD_403_BUTTON=${GUARD_403_BUTTON:-'Kembali ke Dashboard'}
GUARD_404_TITLE=${GUARD_404_TITLE:-"$GUARD_TITLE"}
GUARD_404_BUTTON=${GUARD_404_BUTTON:-'Kembali ke Dashboard'}
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
[[ ${#GUARD_TITLE} -le 80 && ${#GUARD_404_TITLE} -le 80 && ${#GUARD_OWNER_MESSAGE} -le 240 && ${#GUARD_SERVER_MESSAGE} -le 240 && ${#GUARD_403_BUTTON} -le 80 && ${#GUARD_404_BUTTON} -le 80 ]] || { echo 'Teks Guard terlalu panjang.' >&2; exit 1; }
TITLE_PHP=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$GUARD_TITLE")
OWNER_PHP=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$GUARD_OWNER_MESSAGE")
SERVER_PHP=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$GUARD_SERVER_MESSAGE")
export GUARD_TITLE GUARD_OWNER_MESSAGE GUARD_SERVER_MESSAGE GUARD_403_BUTTON GUARD_404_TITLE GUARD_404_BUTTON
O=${OWNER_ID:-1}
cd "$P"
mariadb panel -Nse "SELECT id FROM users WHERE id=$O" | grep -qx "$O" || { echo 'Owner not found'; exit 1; }
B=/root/reviactyl-scoped-guard-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"; cp "$A" "$S" "$B/"
[[ -f "$W" ]] && cp "$W" "$B/"
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
cp "$A" "$A.bak-scoped"
cat >"$A" <<PHP
<?php
namespace App\Http\Middleware;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
class AdminAuthenticate {
 public function handle(Request \$request, \\Closure \$next): mixed {
  \$guardTitle=$TITLE_PHP; \$ownerMessage=$OWNER_PHP; \$serverMessage=$SERVER_PHP;
  \$u=\$request->user(); if (!\$u || !\$u->root_admin) throw new AccessDeniedHttpException();
  if ((int)\$u->id === $O) return \$next(\$request);
  \$p='/'.ltrim(\$request->path(),'/');
  foreach(['/admin/nodes','/admin/locations','/admin/databases','/admin/settings','/admin/api','/admin/application-api','/admin/extensions','/admin/mounts','/admin/nests','/admin/users'] as \$b) if (\$p===\$b || str_starts_with(\$p,\$b.'/')) throw new AccessDeniedHttpException(\$guardTitle . ': ' . \$ownerMessage);
  if (preg_match('#^/admin/users/([0-9]+)(?:/|$)#', \$p, \$m)) { \$target=\\App\\Models\\User::find((int)\$m[1]); if (!\$target || (int)\$target->id !== (int)\$u->id) throw new AccessDeniedHttpException(\$guardTitle . ': ' . \$ownerMessage); }
  if (preg_match('#^/admin/servers/([0-9]+)(?:/|$)#', \$p, \$m)) { \$target=\\App\\Models\\Server::find((int)\$m[1]); if (!\$target || (int)\$target->owner_id !== (int)\$u->id) throw new AccessDeniedHttpException(\$guardTitle . ': ' . \$serverMessage); }
  return \$next(\$request);
 }
}
PHP
python3 - "$S" "$O" <<'PY'
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
PY
php -l "$S"
# The server page is React and its error card has no return button by default.
# Install a small DOM adapter in Blade instead of rewriting hashed JS assets.
# It reads the same Designify 404 settings saved below, so all three values
# entered for "server user lain" (title, message, button) appear together.
python3 - "$W" <<'PY'
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
PY
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
systemctl restart php8.3-fpm nginx reviq
echo "Installed. Backup: $B | Guard title: $GUARD_TITLE"
