# =============================================================================
# Moodle Docker — Imagen personalizada y mantenible
# =============================================================================
# Imagen base: moodlehq/moodle-php-apache:8.4
#   → PHP 8.4 + Apache + todas las extensiones PHP requeridas por Moodle
#
# Para actualizar Moodle, cambia MOODLE_VERSION en .env y ejecuta:
#   make rebuild
# =============================================================================

ARG PHP_VERSION=8.2
FROM moodlehq/moodle-php-apache:${PHP_VERSION}

# ---------------------------------------------------------------------------
# Build arguments — pueden sobreescribirse en docker-compose o en línea
# ---------------------------------------------------------------------------
# Rama estable de Moodle. Opciones:
#   MOODLE_405_STABLE → Moodle 4.5.x (LTS recomendado)
#   MOODLE_404_STABLE → Moodle 4.4.x
#   MOODLE_403_STABLE → Moodle 4.3.x
# ---------------------------------------------------------------------------
ARG MOODLE_VERSION=MOODLE_405_STABLE
ARG MOODLE_REPO=https://github.com/moodle/moodle.git

# Metadata de la imagen
LABEL org.opencontainers.image.title="Moodle LMS"
LABEL org.opencontainers.image.description="Moodle custom Docker image based on moodlehq/moodle-php-apache"
LABEL org.opencontainers.image.source="https://github.com/moodle/moodle"
LABEL moodle.version="${MOODLE_VERSION}"

# ---------------------------------------------------------------------------
# Variables de entorno de runtime (pueden sobreescribirse con -e o en compose)
# ---------------------------------------------------------------------------
# Valores funcionales que no son secretos — los secretos DEBEN venir del .env
ENV MOODLE_WWWROOT=http://localhost:8080 \
    MOODLE_DATAROOT=/var/www/moodledata \
    MOODLE_ADMIN_USER=admin \
    MOODLE_SITE_NAME="My Moodle Site" \
    MOODLE_LANG=es \
    MOODLE_SSLPROXY=false \
    DB_TYPE=pgsql \
    DB_HOST=db \
    DB_PORT=5432 \
    DB_NAME=moodle \
    DB_PREFIX=mdl_ \
    REDIS_HOST=redis \
    REDIS_PORT=6379
# Nota: MOODLE_ADMIN_PASS, MOODLE_ADMIN_EMAIL, DB_USER y DB_PASS
# NO tienen default — DEBEN definirse en .env o docker-compose

# Guarda la versión instalada como env var para introspección en runtime
ENV MOODLE_VERSION_LABEL=${MOODLE_VERSION}

# ---------------------------------------------------------------------------
# Clonar Moodle desde GitHub (shallow clone para reducir tamaño)
# ---------------------------------------------------------------------------
# WORKDIR / es crítico: la imagen base tiene WORKDIR=/var/www/html.
# Si hacemos rm -rf /var/www/html con ese WORKDIR activo, el shell
# pierde su CWD y git falla con "Unable to read current working directory".
WORKDIR /

RUN set -eux; \
    # Limpiar el directorio destino (la imagen base puede tener archivos)
    rm -rf /var/www/html; \
    mkdir -p /var/www/html; \
    # Clonar rama específica, sin historial completo (más rápido, menos espacio)
    git clone \
        --depth 1 \
        --branch "${MOODLE_VERSION}" \
        --single-branch \
        "${MOODLE_REPO}" \
        /var/www/html; \
    # Limpiar metadata de git de la imagen final (ahorra espacio)
    rm -rf /var/www/html/.git; \
    # Permisos correctos para Apache
    chown -R www-data:www-data /var/www/html; \
    chmod -R 755 /var/www/html

# ---------------------------------------------------------------------------
# Directorio de datos de Moodle (moodledata) — siempre fuera del webroot
# ---------------------------------------------------------------------------
RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/moodledata \
    && chmod 0770 /var/www/moodledata

# ---------------------------------------------------------------------------
# Configuración PHP personalizada
# ---------------------------------------------------------------------------
COPY config/php/custom.ini /usr/local/etc/php/conf.d/99-moodle-custom.ini

# ---------------------------------------------------------------------------
# Configuración Apache personalizada
# ---------------------------------------------------------------------------
COPY config/apache/moodle.conf /etc/apache2/sites-available/moodle.conf
RUN a2dissite 000-default.conf 2>/dev/null || true; \
    a2ensite moodle.conf; \
    a2enmod rewrite headers expires

# ---------------------------------------------------------------------------
# Entrypoint personalizado
# ---------------------------------------------------------------------------
COPY scripts/entrypoint.sh /usr/local/bin/moodle-entrypoint.sh
RUN chmod +x /usr/local/bin/moodle-entrypoint.sh

# ---------------------------------------------------------------------------
# Extensiones PHP + dependencias del sistema (una sola capa de apt-get)
# ---------------------------------------------------------------------------
# pdo_pgsql: puede no estar activa en la imagen base, la instalamos explícitamente
# cron: para tareas programadas de Moodle (cada minuto)
# gettext-base: utilidades de localización
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libpq-dev \
        cron \
        gettext-base \
    && docker-php-ext-install pdo_pgsql pgsql \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Cron para tareas programadas de Moodle
# ---------------------------------------------------------------------------
# Formato /etc/cron.d: minuto hora dia mes diasemana USUARIO comando
# IMPORTANTE: el trailing newline es OBLIGATORIO para que cron lo procese.
# NO usar 'crontab' con este archivo — crontab no acepta el campo de usuario.
RUN printf '* * * * * www-data /usr/local/bin/php /var/www/html/admin/cli/cron.php >> /var/log/moodle-cron.log 2>&1\n' \
    > /etc/cron.d/moodle-cron \
    && chmod 0644 /etc/cron.d/moodle-cron

EXPOSE 80

# Sobreescribir el entrypoint de la imagen base con el nuestro
ENTRYPOINT ["/usr/local/bin/moodle-entrypoint.sh"]
CMD ["apache2-foreground"]
