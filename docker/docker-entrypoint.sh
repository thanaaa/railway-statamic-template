#!/bin/sh
set -e

DATA_DIR="/data"
APP_DIR="/var/www/html"
SENTINEL="${DATA_DIR}/.seeded"

echo "==> [entrypoint] Starting Statamic Railway container"

# ── 0. Volume mount guard ─────────────────────────────────────────────────────
# Fail fast with a clear message if /data is not mounted.
# Without this, the container silently uses ephemeral storage and all content
# is lost on every redeploy.
if [ ! -d "${DATA_DIR}" ]; then
    echo "==> [entrypoint] ERROR: ${DATA_DIR} does not exist."
    echo "==> Attach a Railway Volume at /data before deploying."
    exit 1
fi

# ── 1. APP_KEY validation and auto-generation ─────────────────────────────────
# Railway's ${{secret(32)}} generates a raw 32-char string. Laravel requires
# APP_KEY in the format: base64:<base64-encoded-string>
# If APP_KEY is missing or not base64:-prefixed, we generate and persist one.
APP_KEY_FILE="${DATA_DIR}/.app_key"

if [ -z "${APP_KEY}" ] || [ "${APP_KEY#base64:}" = "${APP_KEY}" ]; then
    if [ -f "${APP_KEY_FILE}" ]; then
        export APP_KEY
        APP_KEY="$(cat "${APP_KEY_FILE}")"
        echo "==> [entrypoint] Loaded APP_KEY from volume."
    else
        echo "==> [entrypoint] APP_KEY missing or not in base64: format. Generating..."
        GENERATED_KEY="$(php artisan key:generate --show --no-ansi | tr -d '\r\n')"
        export APP_KEY="${GENERATED_KEY}"
        echo "${GENERATED_KEY}" > "${APP_KEY_FILE}"
        chmod 600 "${APP_KEY_FILE}"
        echo ""
        echo "=========================================================="
        echo " ACTION REQUIRED: Copy this into Railway Variables:"
        echo " APP_KEY=${GENERATED_KEY}"
        echo "=========================================================="
        echo ""
    fi
fi

# ── 2. Volume: seed on FIRST RUN ONLY (sentinel-guarded) ─────────────────────
# CRITICAL: We check for a sentinel file, NOT whether dirs are empty.
# A volume reattachment must never trigger a re-seed that overwrites user content.
if [ ! -f "${SENTINEL}" ]; then
    echo "==> [entrypoint] First run detected — seeding volume from image..."
    mkdir -p "${DATA_DIR}/content" "${DATA_DIR}/storage" "${DATA_DIR}/assets"
    cp -rp "${APP_DIR}/content/." "${DATA_DIR}/content/"
    cp -rp "${APP_DIR}/storage/." "${DATA_DIR}/storage/"

    # Set permissions on first run only (expensive on large volumes).
    chown -R www-data:www-data "${DATA_DIR}"
    chmod -R 755 "${DATA_DIR}/storage"
    chmod -R 755 "${DATA_DIR}/content"

    touch "${SENTINEL}"
    echo "==> [entrypoint] Volume seeded."
fi

# ── 3. Symlinks (recreated on every start) ────────────────────────────────────
# LOCAL DEV GUARD: When docker-compose mounts the repo as a bind mount at
# /var/www/html, rm -rf content/ would destroy the developer's local files.
# Skip the destructive symlink setup in local dev mode.
if [ "${APP_ENV}" != "local" ]; then
    rm -rf "${APP_DIR}/content"
    ln -sf "${DATA_DIR}/content" "${APP_DIR}/content"

    rm -rf "${APP_DIR}/storage"
    ln -sf "${DATA_DIR}/storage" "${APP_DIR}/storage"

    rm -rf "${APP_DIR}/public/assets"
    ln -sf "${DATA_DIR}/assets" "${APP_DIR}/public/assets"
else
    echo "==> [entrypoint] APP_ENV=local — skipping volume symlinks."
fi

# ── 4. Optimize for production (fast, always run) ─────────────────────────────
# Writes config + route + event caches to bootstrap/cache/ using live env vars.
# Must run in entrypoint (not Dockerfile) because APP_KEY/APP_URL are env vars.
# Split into individual commands (not `optimize`) so each failure is visible.
php artisan config:clear  || true   # clear any stale build-time cache first
php artisan config:cache
php artisan route:cache   || true
php artisan view:cache    || true

# ── 5. Warm the Statamic stache (content index) ───────────────────────────────
# Reads all YAML/Markdown from /data/content and writes search indexes to
# /data/storage/statamic/stache. Must run in entrypoint — content is on the volume.
php artisan statamic:stache:warm

# ── 6. Update search indexes (optional — graceful failure) ────────────────────
# If Statamic search is not configured, this is a no-op. || true prevents a
# missing search driver from crashing the container.
php artisan statamic:search:update --all || true

# ── 7. Fix permissions after artisan ─────────────────────────────────────────
# The artisan commands above ran as root and may have created files owned by root
# in storage/ and bootstrap/cache/. php-fpm runs as www-data and cannot write
# to root-owned files. Re-chown after artisan to fix this.
chown -R www-data:www-data \
    "${APP_DIR}/storage" \
    "${APP_DIR}/bootstrap/cache"

# ── 8. Optional: seed first super user from env vars ─────────────────────────
# Set STATAMIC_SUPER_USER_EMAIL + STATAMIC_SUPER_USER_PASSWORD to auto-create
# the first admin user. Only runs if both vars are set AND no user files exist yet.
# IMPORTANT: Remove these vars from Railway dashboard after first successful login.
if [ -n "${STATAMIC_SUPER_USER_EMAIL}" ] && [ -n "${STATAMIC_SUPER_USER_PASSWORD}" ]; then
    # Statamic stores user YAML files in storage/users/ (flat-file driver).
    # Do NOT check storage/statamic/ — that directory contains the stache cache,
    # not user accounts.
    USER_COUNT=$(find "${DATA_DIR}/storage/users" -maxdepth 1 -name "*.yaml" 2>/dev/null | wc -l)
    if [ "${USER_COUNT}" -eq 0 ]; then
        echo "==> [entrypoint] Creating super user from env vars..."
        php please make:user \
            --name="${STATAMIC_SUPER_USER_NAME:-Admin}" \
            --email="${STATAMIC_SUPER_USER_EMAIL}" \
            --password="${STATAMIC_SUPER_USER_PASSWORD}" \
            --super \
            --no-interaction
        echo "==> [entrypoint] Super user created. Remove STATAMIC_SUPER_USER_PASSWORD from Railway vars."
    fi
fi

# ── 9. Generate nginx config with $PORT substituted ───────────────────────────
export PORT="${PORT:-8080}"
envsubst '$PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "==> [entrypoint] Ready. Starting supervisord on port ${PORT}"

# ── 10. Hand off to CMD (supervisord) ────────────────────────────────────────
exec "$@"
