FROM php:8.4-cli

# =========================
# System dependencies
# =========================
RUN apt-get update && apt-get install -y \
    git unzip curl libssl-dev pkg-config libzip-dev \
    build-essential python3 autoconf \
    && apt-get clean

# =========================
# PHP extensions
# =========================
RUN docker-php-ext-install zip

# MongoDB extension (stable install)
RUN pecl install mongodb \
    && docker-php-ext-enable mongodb \
    && echo "extension=mongodb.so" > /usr/local/etc/php/conf.d/mongodb.ini

# Verify MongoDB is installed (fails build if not)
RUN php -m | grep mongodb

# =========================
# Redis (Predis - no ext needed)
# =========================
ENV REDIS_CLIENT=predis

# =========================
# Composer
# =========================
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# =========================
# Install PHP dependencies
# =========================
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-scripts

# =========================
# Copy project files
# =========================
COPY . .

# =========================
# Laravel optimizations
# =========================
RUN php artisan config:clear \
    && php artisan cache:clear \
    && php artisan route:clear

# =========================
# Run server
# =========================
EXPOSE 10000

CMD ["sh", "-lc", "php artisan optimize:clear && php artisan serve --host=0.0.0.0 --port=${PORT:-10000}"]