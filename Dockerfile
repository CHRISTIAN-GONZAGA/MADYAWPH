FROM php:8.4-cli

# =========================
# System dependencies
# =========================
RUN apt-get update && apt-get install -y \
    git unzip curl libssl-dev pkg-config libzip-dev \
    build-essential python3

# PHP extensions
RUN docker-php-ext-install zip

# MongoDB extension
RUN pecl install mongodb \
    && docker-php-ext-enable mongodb

# =========================
# Node.js (LTS)
# =========================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# IMPORTANT: prevent Vite memory crash
ENV NODE_OPTIONS=--max_old_space_size=4096

# =========================
# Composer
# =========================
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Laravel Redis: use Predis (pure PHP). Image does not ship phpredis ext.
ENV REDIS_CLIENT=predis

# =========================
# Install PHP dependencies FIRST
# =========================
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-scripts

# =========================
# Copy full project
# =========================
COPY . .

# =========================
# Install JS + Build Vite
# =========================
RUN npm cache clean --force
RUN npm install
RUN npm run build

# =========================
# Run server
# =========================
EXPOSE 10000

CMD ["sh", "-lc", "php artisan optimize:clear && php artisan serve --host=0.0.0.0 --port=${PORT:-10000}"]