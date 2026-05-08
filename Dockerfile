FROM php:8.4-cli-trixie

RUN docker-php-ext-install pdo_mysql

WORKDIR /app
ENV HOME=/tmp

COPY harvest.php ./harvest.php
COPY sql ./sql

USER 10001:10001

CMD ["php", "/app/harvest.php"]
