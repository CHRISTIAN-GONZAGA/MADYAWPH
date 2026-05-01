FROM php:8.4-cli

# System dependencies
RUN apt-get update && apt-get install -y \
    git unzip curl libssl-dev pkg-config libzip-dev \
    build-essential python3

# PHP extensions
RUN docker-php-ext-install zip

# MongoDB extension
RUN pecl install mongodb \
    && docker-php-ext-enable mongodb

# Node.js (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Copy composer files first (better caching)
COPY composer.json composer.lock ./

# IMPORTANT: disable scripts to avoid package:discover crash
RUN composer install --no-dev --optimize-autoloader --no-scripts

# Copy full project
COPY . .

# Install frontend + build Vite
RUN npm install
RUN npm run build

# Laravel safe setup (avoid crash if env not ready)
RUN php artisan config:clear || true
RUN php artisan cache:clear || true
RUN php artisan package:discover || true
RUN php artisan config:cache || true
RUN php artisan route:cache || true

EXPOSE 10000

CMD php artisan serve --host=0.0.0.0 --port=10000