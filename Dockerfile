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

# Install Node.js (stable LTS version)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Copy only composer files first (better caching)
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader

# Copy rest of project
COPY . .

# Install frontend dependencies + build Vite
RUN npm install
RUN npm run build

# Optimize Laravel
RUN php artisan config:cache || true
RUN php artisan route:cache || true

EXPOSE 10000

CMD php artisan serve --host=0.0.0.0 --port=10000