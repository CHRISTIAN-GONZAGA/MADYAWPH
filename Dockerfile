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

# MongoDB extension
RUN pecl install mongodb \
    && docker-php-ext-enable mongodb

# Verify MongoDB is installed
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
# Fix permissions (important for Laravel)
# =========================
RUN chmod -R 775 storage bootstrap/cache

# =========================
# Run server
# =========================
EXPOSE 10000

RUN chmod +x scripts/render-start.sh

CMD ["sh", "scripts/render-start.sh"]