FROM php:8.4-cli

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git unzip curl libssl-dev pkg-config libzip-dev

# Install PHP extensions
RUN docker-php-ext-install zip

# Install MongoDB extension
RUN pecl install mongodb \
    && docker-php-ext-enable mongodb

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY . .

RUN composer install --no-dev --optimize-autoloader

EXPOSE 10000

CMD php artisan serve --host=0.0.0.0 --port=10000
