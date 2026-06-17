#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# commit-grav-fixes.sh
#
# À exécuter à la racine du dépôt local grav-docs (déjà cloné, contenant
# les fichiers générés lors des sessions précédentes : Dockerfile,
# docker/entrypoint.sh, docker/bootstrap-admin.sh, etc.)
#
# Ce script applique deux corrections issues des tests réels en local :
#
#   1. docker/bootstrap-admin.sh
#      - Séquence stdin corrigée pour correspondre à l'ordre RÉEL des
#        prompts de `bin/plugin login new-user` (Username, Password,
#        Repeat password, Email, Language, Permissions, Admin type,
#        Full name, Title, State) — au lieu de la séquence supposée
#        initialement (incomplète).
#      - Réponse "admin" ajoutée pour le prompt "Admin type".
#      - "Full name" fixé en dur à "Administrator" (champ obligatoire,
#        pas de variable d'environnement dédiée pour l'instant).
#
#   2. docker/entrypoint.sh
#      - Correction des permissions runtime Grav : chown + chmod sur
#        cache/, logs/, images/, assets/, en plus de user/, avant le
#        démarrage de php-fpm/nginx. Corrige l'erreur
#        "RuntimeException: Failed to save file /var/www/html/cache/..."
#        constatée au premier accès après bootstrap.
#
# Le script ne touche PAS à main : il committe sur la branche courante.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── 0. Vérifications préliminaires ───────────────────────────────────────────

echo "==> Vérification du dépôt..."

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERREUR : ce répertoire n'est pas un dépôt git."
  echo "Lance ce script depuis la racine de grav-docs."
  exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)
echo "    Branche actuelle : $CURRENT_BRANCH"

for f in docker/entrypoint.sh docker/bootstrap-admin.sh Dockerfile; do
  if [ ! -f "$f" ]; then
    echo "ERREUR : '$f' introuvable. Vérifie que tu es à la racine du dépôt grav-docs."
    exit 1
  fi
done

echo "    OK — fichiers attendus présents."

# ── 1. Écriture de docker/bootstrap-admin.sh (séquence stdin corrigée) ───────

echo ""
echo "==> Mise à jour de docker/bootstrap-admin.sh..."

cat > docker/bootstrap-admin.sh << 'BOOTSTRAP_EOF'
#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap-admin.sh
#
# Crée optionnellement un compte administrateur Grav au démarrage du conteneur,
# en utilisant la CLI officielle du plugin login (bin/plugin login new-user).
#
# Comportement :
#   - Si GRAV_ADMIN_USER, GRAV_ADMIN_PASSWORD ou GRAV_ADMIN_EMAIL est absent
#     ou vide : ne fait rien (bootstrap optionnel).
#   - Si le compte user/accounts/<GRAV_ADMIN_USER>.yaml existe déjà : ne fait
#     rien (ne jamais écraser un compte existant).
#   - Si le plugin "login" n'est pas installé dans l'image : log une erreur
#     explicite et s'arrête, sans tenter de générer un hash de mot de passe
#     manuellement.
#   - Le mot de passe n'est jamais passé en argument de ligne de commande
#     (donc jamais visible dans `ps aux` ou /proc/<pid>/cmdline). Il est
#     fourni à `bin/plugin login new-user` via stdin, en mode interactif.
#   - Aucun secret n'est écrit dans les logs.
#   - Un échec du bootstrap n'empêche jamais le démarrage du conteneur :
#     ce script ne doit jamais faire échouer entrypoint.sh.
#
# Appelé depuis docker/entrypoint.sh, après l'initialisation du volume
# /var/www/html/user et avant le démarrage de php-fpm/nginx.
# ─────────────────────────────────────────────────────────────────────────────

GRAV_ROOT="/var/www/html"
ACCOUNTS_DIR="$GRAV_ROOT/user/accounts"
LOGIN_PLUGIN_DIR="$GRAV_ROOT/user/plugins/login"

log() {
  echo "[bootstrap-admin] $1"
}

# ── 1. Bootstrap optionnel : sortie immédiate si une variable manque ─────────

if [ -z "$GRAV_ADMIN_USER" ] || [ -z "$GRAV_ADMIN_PASSWORD" ] || [ -z "$GRAV_ADMIN_EMAIL" ]; then
  log "GRAV_ADMIN_USER / GRAV_ADMIN_PASSWORD / GRAV_ADMIN_EMAIL not fully set — skipping admin bootstrap."
  exit 0
fi

# ── 2. Ne jamais écraser un compte existant ───────────────────────────────────

ACCOUNT_FILE="$ACCOUNTS_DIR/${GRAV_ADMIN_USER}.yaml"

if [ -f "$ACCOUNT_FILE" ]; then
  log "Account '$GRAV_ADMIN_USER' already exists ($ACCOUNT_FILE) — skipping bootstrap."
  exit 0
fi

# ── 3. Vérifier la présence du plugin login (pas de fallback manuel) ─────────

if [ ! -d "$LOGIN_PLUGIN_DIR" ]; then
  log "ERROR: login plugin not found at $LOGIN_PLUGIN_DIR."
  log "ERROR: cannot bootstrap admin account without the official Grav CLI."
  log "ERROR: install it via 'bin/gpm install login' or rebuild the image with the plugin included."
  exit 0
fi

# ── 4. Création du compte via la CLI officielle, mot de passe fourni par stdin

log "Bootstrapping admin account '$GRAV_ADMIN_USER' via bin/plugin login new-user..."

cd "$GRAV_ROOT" || {
  log "ERROR: cannot cd into $GRAV_ROOT."
  exit 0
}

# Ordre RÉEL des prompts interactifs de `bin/plugin login new-user`
# (constaté en test, différent de la séquence documentée initialement) :
#   1. Username
#   2. Password
#   3. Repeat password
#   4. Email
#   5. Language          (vide = défaut)
#   6. Permissions        ([a] admin / [s] site / [b] admin+site)
#   7. Admin type          ([admin] / [api] / [both])
#   8. Full name           (OBLIGATOIRE — une valeur vide fait échouer la validation)
#   9. Title               (vide = défaut)
#  10. State                ([enabled]/disabled, vide = enabled par défaut)
#
# Permissions choisies : b (admin + site), conformément à la décision validée.
# Admin type choisi : admin (permissions classiques Grav Admin, pas "api"/"both").
# Full name : valeur fixe "Administrator" puisque ce champ est obligatoire et
# qu'aucune variable d'environnement dédiée n'a été demandée pour le piloter.
# Le mot de passe (saisi deux fois) ne transite que par ce flux stdin,
# jamais en argument CLI.

BOOTSTRAP_OUTPUT=$(
  printf '%s\n%s\n%s\n%s\n\nb\nadmin\nAdministrator\n\n\n' \
    "$GRAV_ADMIN_USER" \
    "$GRAV_ADMIN_PASSWORD" \
    "$GRAV_ADMIN_PASSWORD" \
    "$GRAV_ADMIN_EMAIL" \
  | bin/plugin login new-user 2>&1
)
BOOTSTRAP_STATUS=$?

# On ne logue jamais la sortie brute si elle pouvait contenir un secret.
# La CLI officielle n'échote pas le mot de passe dans sa sortie de confirmation
# (uniquement les prompts suivis de "Success! User X created."), mais on filtre
# par prudence toute ligne qui contiendrait littéralement le mot de passe.
SAFE_OUTPUT=$(printf '%s' "$BOOTSTRAP_OUTPUT" | grep -v -F "$GRAV_ADMIN_PASSWORD")

if [ "$BOOTSTRAP_STATUS" -eq 0 ] && [ -f "$ACCOUNT_FILE" ]; then
  log "Admin account '$GRAV_ADMIN_USER' created successfully."
  chown www-data:www-data "$ACCOUNT_FILE" 2>/dev/null || true
else
  log "WARNING: admin bootstrap did not complete successfully (exit code $BOOTSTRAP_STATUS)."
  log "WARNING: CLI output (password redacted):"
  printf '%s\n' "$SAFE_OUTPUT" | while IFS= read -r line; do
    log "  $line"
  done
  log "WARNING: container will continue starting without a bootstrapped admin account."
fi

exit 0
BOOTSTRAP_EOF

chmod +x docker/bootstrap-admin.sh
echo "    OK"

# ── 2. Écriture de docker/entrypoint.sh (permissions runtime corrigées) ──────

echo ""
echo "==> Mise à jour de docker/entrypoint.sh..."

cat > docker/entrypoint.sh << 'ENTRYPOINT_EOF'
#!/bin/sh
set -e

if [ ! -f /var/www/html/user/.initialized ]; then
  echo "Initializing Grav user directory..."
  rsync -a /tmp/grav-user/ /var/www/html/user/
  touch /var/www/html/user/.initialized
fi

chown -R www-data:www-data /var/www/html/user

# Correction des permissions des répertoires runtime Grav.
# Sans cela, Grav échoue au premier accès avec une erreur du type :
#   RuntimeException: Failed to save file /var/www/html/cache/compiled/...
# car ces répertoires (créés ou régénérés à l'exécution) ne sont pas
# forcément inscriptibles par www-data, notamment lorsque /var/www/html/user
# est un volume monté avec des permissions héritées de l'hôte.
chown -R www-data:www-data \
  /var/www/html/cache \
  /var/www/html/logs \
  /var/www/html/images \
  /var/www/html/assets \
  /var/www/html/user \
  2>/dev/null || true

chmod -R u+rwX,g+rwX \
  /var/www/html/cache \
  /var/www/html/logs \
  /var/www/html/images \
  /var/www/html/assets \
  /var/www/html/user \
  2>/dev/null || true

# Bootstrap optionnel d'un compte administrateur (no-op si les variables
# GRAV_ADMIN_USER / GRAV_ADMIN_PASSWORD / GRAV_ADMIN_EMAIL ne sont pas
# définies, ou si le compte existe déjà). Ne fait jamais échouer le démarrage.
/bootstrap-admin.sh || true

php-fpm -D
nginx -g "daemon off;"
ENTRYPOINT_EOF

chmod +x docker/entrypoint.sh
echo "    OK"

# ── 3. Staging des fichiers concernés uniquement ──────────────────────────────

echo ""
echo "==> Ajout des fichiers concernés au staging git..."

git add docker/bootstrap-admin.sh docker/entrypoint.sh

git diff --cached --name-only | sed 's/^/      /'

UNSTAGED=$(git diff --name-only)
if [ -n "$UNSTAGED" ]; then
  echo ""
  echo "ATTENTION : des modifications non stagées existent ailleurs dans le dépôt :"
  echo "$UNSTAGED" | sed 's/^/      /'
  echo "Elles ne seront PAS incluses dans ce commit (comportement voulu)."
fi

# ── 4. Commit ─────────────────────────────────────────────────────────────────

echo ""
echo "==> Commit..."
git commit -m "fix: correct admin bootstrap prompt sequence and Grav runtime permissions

Based on real-world local testing of the admin bootstrap feature.

1. docker/bootstrap-admin.sh
   - The actual prompt sequence of \`bin/plugin login new-user\` differs
     from what was initially assumed. Real order observed:
     Username, Password, Repeat password, Email, Language, Permissions,
     Admin type, Full name, Title, State.
   - Added response for the new 'Admin type' prompt ([admin]/[api]/[both]):
     answer 'admin' to get standard Grav Admin permissions.
   - 'Full name' is a required field (validation fails if empty); fixed to
     the literal value 'Administrator'. No GRAV_ADMIN_FULLNAME variable is
     introduced for now, per explicit decision to keep the bootstrap scope
     limited to GRAV_ADMIN_USER / GRAV_ADMIN_PASSWORD / GRAV_ADMIN_EMAIL.
   - Password is still never passed as a CLI argument; it is provided
     twice (initial + repeat) via stdin only.

2. docker/entrypoint.sh
   - Fixed Grav runtime permissions: chown + chmod now also cover
     cache/, logs/, images/, assets/ (previously only user/ was covered).
   - Without this fix, Grav fails on first access with:
     RuntimeException: Failed to save file /var/www/html/cache/compiled/...
   - Applied before starting php-fpm/nginx, after volume initialization
     and before the optional admin bootstrap."

echo "    OK"

# ── 5. Résumé ─────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " COMMIT CRÉÉ SUR LA BRANCHE : $CURRENT_BRANCH"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo " Prochaines étapes :"
echo "   1. git push (si tu veux pousser maintenant)"
echo "   2. Rebuild et re-tester localement :"
echo "      docker compose build"
echo "      docker compose up -d"
echo "   3. Vérifier à nouveau le bootstrap admin + l'accès /admin sans erreur"
echo "      RuntimeException."
echo ""
