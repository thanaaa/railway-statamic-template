# Statamic on Railway

One-click self-hosted [Statamic](https://statamic.com) CMS on [Railway](https://railway.app).

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/PLACEHOLDER)

---

## What's included

- **PHP 8.3** (Alpine) + **nginx** + **php-fpm** + **supervisord** in a single container
- **Railway Volume** at `/data` for persistent flat-file content, storage, and uploaded assets
- **APP_KEY auto-generation** — no manual key setup required on first deploy
- **Laravel task scheduler** via `schedule:work` (Statamic cron jobs run automatically)
- Hardened nginx config: real IP headers, HTTPS detection, HSTS, static file serving, Glide image transforms

---

## First deploy checklist

### 1. Deploy

Click the button above. Railway will build the image (~3–5 minutes).

### 2. Copy APP_KEY from logs

Open the deployment logs and look for:

```
==========================================================
 ACTION REQUIRED: Copy this into Railway Variables:
 APP_KEY=base64:...
==========================================================
```

Copy that value into **Railway Variables → APP_KEY**.

### 3. Set APP_URL

In Railway Variables, set:

```
APP_URL=https://<your-railway-domain>.railway.app
```

### 4. Trigger a redeploy

After setting APP_KEY and APP_URL, trigger a manual redeploy from the Railway dashboard.

### 5. Create your first user

**Option A — via env vars (recommended for first deploy):**

Set these Railway Variables before deploying:

```
STATAMIC_SUPER_USER_EMAIL=you@example.com
STATAMIC_SUPER_USER_PASSWORD=a-strong-password
STATAMIC_SUPER_USER_NAME=Admin
```

The user is created automatically on first boot if no users exist yet.

> ⚠️ **Remove `STATAMIC_SUPER_USER_PASSWORD` from Railway Variables after your first login.** The password is visible to anyone with dashboard access while it's set.

**Option B — via Railway Shell:**

In the Railway dashboard, open the **Shell** tab and run:

```sh
php please make:user
```

### 6. Log in

Visit `https://<your-domain>/cp` and log in with your admin credentials.

---

## How data is persisted

A Railway Volume is mounted at `/data`. On first boot, starter content is seeded there. After that, a sentinel file (`/data/.seeded`) prevents any re-seed from overwriting your data.

```
/data/
├── .seeded         ← Sentinel: prevents re-seed on redeploy
├── .app_key        ← Auto-generated APP_KEY (copy to Railway Variables)
├── content/        ← Statamic flat-file content (YAML/Markdown)
├── storage/        ← Laravel cache, sessions, Statamic stache
└── assets/         ← Uploaded media files
```

The application directory uses symlinks so Laravel/Statamic see these paths at their expected locations.

---

## Upgrading Statamic

```sh
# Locally:
composer update statamic/cms
git add composer.json composer.lock vendor/
git commit -m "chore: upgrade statamic/cms"
git push
```

Railway will rebuild and redeploy automatically.

---

## Local development

**For active content editing** (recommended):

```sh
composer install
cp .env.example .env
php artisan key:generate
php artisan serve
```

**For testing the production container:**

```sh
# Update the APP_KEY in docker-compose.yml first, then:
docker compose up --build
```

> The `docker-compose.yml` uses a named volume for `/data` to mirror Railway. Do **not** bind-mount the source directory into the container — the entrypoint's symlink setup would destroy your local `content/` and `storage/` directories.

---

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `APP_KEY` | Yes (auto-generated) | Laravel encryption key. Auto-generated on first boot and printed to logs. |
| `APP_URL` | Yes | Your Railway public URL, e.g. `https://mysite.railway.app` |
| `APP_NAME` | No | Site name shown in Statamic CP |
| `STATAMIC_LICENSE_KEY` | No | Required for Statamic Pro features |
| `STATAMIC_SUPER_USER_EMAIL` | No | Auto-creates first admin on boot |
| `STATAMIC_SUPER_USER_PASSWORD` | No | ⚠️ Remove after first login |
| `MAIL_MAILER` | No | Mail driver. Default: `log` (emails go to container logs) |

See `.env.example` for the full list.

---

## Known limitations

- **Statamic Free = one CP user.** Multi-user teams require [Statamic Pro](https://statamic.com/pricing).
- **Single instance only.** Railway volumes are single-attach — do not run multiple replicas.
- **Brief 502 during redeploy** (~10–30 seconds). This is expected for single-instance deployments.
- **No automatic volume backups** on Railway Hobby plan. Periodically commit `content/` to git as a backup.
- **Custom domain:** After adding a custom domain in Railway, update `APP_URL` and run `php artisan config:clear` via the Shell tab.

---

## Starter kits

This template ships a blank Statamic install. For a richer starting point, check out:

- [Statamic Peak](https://statamic.com/starter-kits/studio1902/peak) — full-featured, opinionated starter
- [Cool Writings](https://statamic.com/starter-kits/statamic/cool-writings) — blog starter

Install a starter kit locally, then push to Railway.

---

## Stack

- [Statamic](https://statamic.com) — flat-file CMS built on Laravel
- [Laravel](https://laravel.com) 12
- PHP 8.3 / Alpine Linux
- nginx + php-fpm + supervisord
- [Railway](https://railway.app)
