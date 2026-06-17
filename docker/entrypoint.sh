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
