# Builder container
FROM php:8.0-fpm-bullseye as builder
COPY --from=composer /usr/bin/composer /usr/bin/composer
RUN apt-get update && \
    apt-get -y install git zip unzip
COPY ./src .
RUN composer config -g repos.packagist composer https://packagist.jp
RUN composer install

###
### npm install & build via vite
###

FROM node:22.2.0-alpine3.20 as vite-builder

WORKDIR /app

COPY ./src/package*.json ./
RUN npm install

COPY ./src .
RUN npm run build

# Release container
FROM php:8.1.18-fpm-alpine3.17

# timezone設定
RUN set -eux && \
    apk add --update-cache --no-cache --virtual=.build-dependencies tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del .build-dependencies

# curl 更新
RUN apk update && apk upgrade curl && apk upgrade pkgconf

# PHP-extensionインストール
RUN apk add autoconf gcc g++ make pkgconfig zlib-dev libmemcached-dev
RUN pecl install redis memcached && \
    docker-php-ext-enable redis && \
    docker-php-ext-enable memcached && \
    docker-php-ext-install bcmath pdo_mysql opcache

# 実行ユーザー追加
RUN addgroup -S app && adduser -S -g app app
RUN chown -R app:app /var/www/html
# ファイルコピー
COPY --chown=app:app --from=builder /var/www/html .
COPY --chown=app:app --from=vite-builder /app/ .
COPY --chown=app:app --from=builder /var/www/html/.env.stg ./.env
COPY ./container/stg/app/php.ini /usr/local/etc/php/php.ini
COPY ./container/stg/app/www.conf /usr/local/etc/php-fpm.d/www.conf

# 不要ファイル削除
# RUN rm .env.* && \
#     rm -r container

# readonly用Volume定義
VOLUME ["/tmp", "/var/www/html/storage/logs", "/var/www/html/storage/framework/views"]
