ARG PHP_BASE_IMAGE
FROM ${PHP_BASE_IMAGE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev \
    && docker-php-ext-install -j1 pgsql pdo_pgsql opcache \
    && rm -rf /var/lib/apt/lists/*
