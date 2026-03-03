FROM php:8.3-fpm-alpine

# ── System deps ───────────────────────────────────────────────────────────────
# Install runtime libraries first, then build-time headers in a virtual group.
# The virtual group is deleted after extension compilation, saving ~50 MB.
RUN apk add --no-cache \
        nginx supervisor curl zip unzip gettext \
        libpng libjpeg-turbo libwebp libzip \
        oniguruma libxml2 \
    && apk add --no-cache --virtual .build-deps \
        libpng-dev libjpeg-turbo-dev libwebp-dev libzip-dev \
        oniguruma-dev libxml2-dev autoconf g++ make \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
       gd exif zip bcmath mbstring pdo tokenizer xml ctype opcache \
    && docker-php-ext-enable opcache \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/* /tmp/*

# ── PHP configuration ─────────────────────────────────────────────────────────
COPY docker/opcache.ini /usr/local/etc/php/conf.d/opcache.ini
COPY docker/php.ini     /usr/local/etc/php/conf.d/app.ini
COPY docker/php-fpm-pool.conf /usr/local/etc/php-fpm.d/www.conf

# ── Application ───────────────────────────────────────────────────────────────
WORKDIR /var/www/html
COPY --chown=www-data:www-data . .

# Publish Statamic CP vendor assets into the image at build time.
# This is deterministic and has no env var dependency.
# The result lands in public/vendor/statamic/ (part of the image layer).
RUN php artisan statamic:install --ansi

# Clear any cached config that may have been created during composer install.
# These caches are baked with build-time env vars — they must be regenerated
# at runtime with the real env vars (APP_KEY, APP_URL, etc.).
RUN rm -f bootstrap/cache/*.php

# Pre-create all directories nginx needs on Alpine. Alpine's nginx package does
# not create these automatically — missing them causes nginx to crash on start.
RUN mkdir -p \
        /run \
        /var/run/nginx \
        /var/lib/nginx/tmp/client_body \
        /var/lib/nginx/tmp/proxy \
        /var/lib/nginx/tmp/fastcgi \
        /var/cache/nginx

# Set base permissions
RUN chmod +x docker/docker-entrypoint.sh \
    && chown -R www-data:www-data \
        /var/www/html \
        /var/run/nginx \
        /var/lib/nginx \
        /var/cache/nginx \
    && chmod -R 755 /var/www/html/storage \
    && chmod -R 755 /var/www/html/bootstrap/cache \
    && chmod -R 755 /var/www/html/content

# ── Runtime config ────────────────────────────────────────────────────────────
COPY docker/nginx.conf.template   /etc/nginx/nginx.conf.template
COPY docker/supervisord.conf      /etc/supervisor/conf.d/supervisord.conf

EXPOSE 8080

# nginx graceful shutdown signal (SIGQUIT = drain connections, SIGTERM = fast kill)
STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -qO- http://127.0.0.1:${PORT:-8080}/up || exit 1

# ENTRYPOINT handles setup; CMD is the actual process so it can be overridden at runtime.
# Inside entrypoint.sh: exec "$@" hands off to supervisord.
ENTRYPOINT ["docker/docker-entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
