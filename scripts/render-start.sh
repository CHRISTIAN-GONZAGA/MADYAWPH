#!/bin/sh
set -e

UPLOAD_ROOT="${FILESYSTEM_UPLOAD_ROOT:-/var/data/uploads}"

php artisan optimize:clear

mkdir -p "$UPLOAD_ROOT"
chmod -R 775 "$UPLOAD_ROOT" 2>/dev/null || true

# Persistent disk (Render): create upload folders + migrate legacy ephemeral files.
php artisan uploads:ensure-persistent --quiet

exec php artisan serve --host=0.0.0.0 --port="${PORT:-10000}"
