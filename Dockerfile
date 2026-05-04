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

# Laravel Redis: use Predis (pure PHP). Image does not ship phpredis ext.
ENV REDIS_CLIENT=predis

# =========================
# Composer
# =========================
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

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
# Run server
# =========================
EXPOSE 10000

CMD ["sh", "-lc", "php artisan optimize:clear && php artisan serve --host=0.0.0.0 --port=${PORT:-10000}"]
