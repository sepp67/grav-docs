#!/bin/sh
set -e

# ─────────────────────────────────────────────────────────────────────────────
# fix_grav_permissions
#
# Crée explicitement les répertoires runtime nécessaires à Grav, puis force
# leur propriété et leurs droits à www-data, l'utilisateur sous lequel
# php-fpm tourne (voir docker/php-fpm.conf).
#
# Pourquoi cette fonction doit être appelée DEUX FOIS (avant ET après le
# bootstrap admin) :
#   bin/plugin login new-user (exécuté en root par bootstrap-admin.sh) génère
#   lui-même des fichiers de cache compilé (ex: cache/compiled/blueprints/
#   master-cli.php) au moment où il s'exécute. Ces fichiers sont donc créés
#   root:root. Si on ne corrige les permissions qu'AVANT le bootstrap, ces
#   fichiers créés PENDANT le bootstrap restent root:root, et php-fpm
#   (www-data) ne peut plus les réécrire ensuite — d'où l'erreur :
#     RuntimeException: Failed to save file /var/www/html/cache/compiled/...
#
# Diagnostic confirmé en local le 2026-06-17 :
#   /var/www/html/cache/compiled            root:root
#   /var/www/html/cache/compiled/blueprints root:root
#   master-cli.php                          root:root (créé par le bootstrap)
# ─────────────────────────────────────────────────────────────────────────────
fix_grav_permissions() {
  mkdir -p \
    /var/www/html/cache/compiled/blueprints \
    /var/www/html/logs \
    /var/www/html/images \
    /var/www/html/assets \
    /var/www/html/user/accounts \
    /var/www/html/user/data \
    /var/www/html/user/config \
    /var/www/html/user/pages \
    /var/www/html/user/plugins \
    /var/www/html/user/themes

  chown -R www-data:www-data \
    /var/www/html/cache \
    /var/www/html/logs \
    /var/www/html/images \
    /var/www/html/assets \
    /var/www/html/user

  chmod -R u+rwX,g+rwX \
    /var/www/html/cache \
    /var/www/html/logs \
    /var/www/html/images \
    /var/www/html/assets \
    /var/www/html/user
}

if [ ! -f /var/www/html/user/.initialized ]; then
  echo "Initializing Grav user directory..."
  rsync -a /tmp/grav-user/ /var/www/html/user/
  touch /var/www/html/user/.initialized
fi

# 1er passage : avant le bootstrap, pour que bin/plugin login new-user
# trouve déjà des répertoires existants et accessibles.
fix_grav_permissions

# Bootstrap optionnel d'un compte administrateur (no-op si les variables
# GRAV_ADMIN_USER / GRAV_ADMIN_PASSWORD / GRAV_ADMIN_EMAIL ne sont pas
# définies, ou si le compte existe déjà). Ne fait jamais échouer le démarrage.
/bootstrap-admin.sh || true

# 2e passage : après le bootstrap, pour reprendre la propriété de tout ce
# que bin/plugin login new-user a pu créer en root pendant son exécution
# (notamment cache/compiled/blueprints/master-cli.php).
fix_grav_permissions

php-fpm -D
nginx -g "daemon off;"
