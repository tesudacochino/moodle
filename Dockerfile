# =============================================================================
# Moodle Docker — Imagen personalizada y mantenible
# =============================================================================
# Imagen base: php:8.3-apache-bookworm (imagen OFICIAL de Docker, no la de
#   moodlehq/moodle-php-apache). moodlehq advierte explícitamente que su
#   imagen "is not intended for production" (lleva xdebug, xhprof, pcov,
#   fixtures de test...) y además tardó varios días en publicar el parche
#   de un CVE crítico (CVE-2026-109618/109619, CVSS 9.2, 2026-10-21) — la
#   imagen oficial de PHP reaccionó en ~8h. Por eso instalamos aquí mismo
#   solo las extensiones que Moodle necesita de verdad, sin herramientas
#   de debug (ver https://docs.moodle.org/502/en/PHP).
#
# Para actualizar Moodle, cambia MOODLE_VERSION en .env y ejecuta:
#   make rebuild
# =============================================================================

ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-apache-bookworm

# ---------------------------------------------------------------------------
# Build arguments — pueden sobreescribirse en docker-compose o en línea
# ---------------------------------------------------------------------------
# Rama estable de Moodle. Opciones:
#   MOODLE_502_STABLE → Moodle 5.2.x (recomendado — requiere PHP >= 8.3)
#   MOODLE_500_STABLE → Moodle 5.0.x
#   MOODLE_405_STABLE → Moodle 4.5.x (LTS)
# ---------------------------------------------------------------------------
ARG MOODLE_VERSION=MOODLE_502_STABLE
ARG MOODLE_REPO=https://github.com/moodle/moodle.git
# SHA del commit HEAD de la rama en el momento del build. No se usa para nada
# más que invalidar la caché de Docker cuando hay un parche nuevo en la rama
# upstream (ej. rebuilds programados) — si no cambia, la capa de git clone
# se serviría desde caché y el build ignoraría los nuevos commits.
ARG MOODLE_COMMIT_SHA=""

# Metadata de la imagen
LABEL org.opencontainers.image.title="Moodle LMS"
LABEL org.opencontainers.image.description="Moodle custom Docker image based on the official php:apache image"
LABEL org.opencontainers.image.source="https://github.com/moodle/moodle"
LABEL moodle.version="${MOODLE_VERSION}"

# ---------------------------------------------------------------------------
# Extensiones PHP requeridas por Moodle (sin extras de desarrollo/debug)
# ---------------------------------------------------------------------------
# ctype, curl, dom, iconv, json, mbstring, pcre, simplexml, spl, xml, sodium,
# tokenizer y opcache ya vienen activados en la imagen base php:*-apache.
# Solo instalamos lo que falta de verdad. Stack de BD: solo PostgreSQL —
# es lo único que usa este proyecto, no se instala mysqli/pdo_mysql.
# pdo_pgsql: Moodle en sí usa el driver nativo pgsql, no PDO, pero
# scripts/entrypoint.sh sí usa PDO (new PDO(...)) para comprobar que la BD
# está arriba — probado en local, sin esto el entrypoint nunca arranca.
# ghostscript/sassc: dependencias en tiempo de ejecución que Moodle invoca
# (conversión de PDF, compilación de temas SCSS), no solo de build.
RUN set -eux; \
    BUILD_DEPS="libfreetype6-dev libjpeg62-turbo-dev libicu-dev libpq-dev libxslt1-dev libldap2-dev libzip-dev"; \
    RUNTIME_DEPS="libfreetype6 libjpeg62-turbo libicu72 libpq5 libxslt1.1 libldap-2.5-0 libzip4 \
        ghostscript sassc unzip zip gettext-base git cron"; \
    apt-get update; \
    apt-get install -y --no-install-recommends $BUILD_DEPS $RUNTIME_DEPS; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-configure ldap; \
    docker-php-ext-configure zip --with-zip; \
    docker-php-ext-install -j"$(nproc)" gd intl pgsql pdo_pgsql zip soap xsl exif ldap opcache; \
    pecl install redis apcu igbinary; \
    docker-php-ext-enable redis apcu igbinary; \
    echo 'apc.enable_cli = On' >> /usr/local/etc/php/conf.d/10-docker-php-ext-apcu.ini; \
    pecl clear-cache; \
    apt-get purge -y --auto-remove $BUILD_DEPS; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/pear

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
    # (no-op — solo referenciado para invalidar la caché de esta capa en cada commit nuevo)
    echo "Moodle commit objetivo: ${MOODLE_COMMIT_SHA:-desconocido}"; \
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
# __DOCUMENT_ROOT__ se resuelve aquí mismo, en build time: si el checkout de
# Moodle trae /public (Moodle >= 5.1) servimos desde ahí, si no (< 5.1),
# servimos desde la raíz. Así no hace falta acordarse de ajustarlo a mano
# en cada rama de versión nueva.
COPY config/apache/moodle.conf /etc/apache2/sites-available/moodle.conf
RUN set -eux; \
    if [ -d /var/www/html/public ]; then \
        DOCROOT=/var/www/html/public; \
    else \
        DOCROOT=/var/www/html; \
    fi; \
    sed -i "s#__DOCUMENT_ROOT__#${DOCROOT}#g" /etc/apache2/sites-available/moodle.conf; \
    a2dissite 000-default.conf 2>/dev/null || true; \
    a2ensite moodle.conf; \
    a2enmod rewrite headers expires

# ---------------------------------------------------------------------------
# Entrypoint personalizado
# ---------------------------------------------------------------------------
COPY scripts/entrypoint.sh /usr/local/bin/moodle-entrypoint.sh
RUN chmod +x /usr/local/bin/moodle-entrypoint.sh

# ---------------------------------------------------------------------------
# Cron para tareas programadas de Moodle
# ---------------------------------------------------------------------------
# Formato /etc/cron.d: minuto hora dia mes diasemana USUARIO comando
# IMPORTANTE: el trailing newline es OBLIGATORIO para que cron lo procese.
# NO usar 'crontab' con este archivo — crontab no acepta el campo de usuario.
RUN printf '* * * * * www-data /usr/local/bin/php /var/www/html/admin/cli/cron.php >> /var/log/moodle-cron.log 2>&1\n' \
    > /etc/cron.d/moodle-cron \
    && chmod 0644 /etc/cron.d/moodle-cron \
    && touch /var/log/moodle-cron.log \
    && chown www-data:www-data /var/log/moodle-cron.log \
    && chmod 0660 /var/log/moodle-cron.log

EXPOSE 80

# Sobreescribir el entrypoint de la imagen base con el nuestro
ENTRYPOINT ["/usr/local/bin/moodle-entrypoint.sh"]
CMD ["apache2-foreground"]
