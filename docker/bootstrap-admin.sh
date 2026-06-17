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
