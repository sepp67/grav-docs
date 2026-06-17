FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
    nginx \
    curl \
    unzip \
    git \
    bash \
    rsync \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    icu-dev \
    oniguruma-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd zip intl mbstring opcache

WORKDIR /var/www/html

RUN curl -L https://getgrav.org/download/core/grav-admin/latest -o grav.zip \
    && unzip grav.zip \
    && DIR="$(find . -maxdepth 1 -type d -name 'grav*' | head -n 1)" \
    && cp -a "$DIR"/. . \
    && rm -rf "$DIR" grav.zip \
    && chown -R www-data:www-data /var/www/html

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/bootstrap-admin.sh /bootstrap-admin.sh
COPY grav/user /tmp/grav-user

RUN chmod +x /entrypoint.sh /bootstrap-admin.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
