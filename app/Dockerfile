FROM php:8.4-fpm-alpine

RUN apk add --no-cache \
    bash \
    git \
    curl \
    zip \
    unzip \
    autoconf \
    g++ \
    make \
    libpng-dev \
    libzip-dev \
    oniguruma-dev \
  && docker-php-ext-install \
    pdo_mysql \
    mbstring \
    zip \
    bcmath \
    pcntl

# Redis
RUN pecl install redis && docker-php-ext-enable redis

# Datadog ddtrace
RUN curl -LO https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php \
  && php datadog-setup.php --php-bin=all \
  && rm datadog-setup.php

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# 依存パッケージ
COPY src/composer.json src/composer.lock ./
RUN composer install --no-scripts --no-autoloader --prefer-dist

# アプリケーションコードをコピー
COPY src/ .
RUN composer dump-autoload --optimize

# ストレージのパーミッション
RUN chown -R www-data:www-data storage bootstrap/cache

EXPOSE 9000
CMD ["php-fpm"]
