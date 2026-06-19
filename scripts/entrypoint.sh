#!/bin/bash
# =============================================================================
# Moodle Docker — Entrypoint personalizado
# =============================================================================
# Este script se ejecuta al arrancar el contenedor y:
#
#   1. Genera /var/www/html/config.php desde variables de entorno
#   2. Detecta si es primera instalación → instala la base de datos
#   3. Detecta si hay upgrade pendiente → ejecuta upgrade
#   4. Configura permisos de moodledata
#   5. Arranca cron en background
#   6. Pasa control al CMD original (apache2-foreground)
#
# =============================================================================
set -euo pipefail

# ─── Colores para logs ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()    { echo -e "${BLUE}[Moodle]${NC} $*"; }
log_ok() { echo -e "${GREEN}[Moodle]${NC} ✅ $*"; }
log_warn(){ echo -e "${YELLOW}[Moodle]${NC} ⚠️  $*"; }
log_err(){ echo -e "${RED}[Moodle]${NC} ❌ $*"; }

# ─── Variables con defaults ───────────────────────────────────────────────────
MOODLE_WWWROOT="${MOODLE_WWWROOT:-http://localhost:8080}"
MOODLE_DATAROOT="${MOODLE_DATAROOT:-/var/www/moodledata}"
MOODLE_ADMIN_USER="${MOODLE_ADMIN_USER:-admin}"
MOODLE_ADMIN_PASS="${MOODLE_ADMIN_PASS:-Admin1234!}"
MOODLE_ADMIN_EMAIL="${MOODLE_ADMIN_EMAIL:-admin@example.com}"
MOODLE_SITE_NAME="${MOODLE_SITE_NAME:-My Moodle Site}"
MOODLE_LANG="${MOODLE_LANG:-es}"
# true = Moodle está detrás de un reverse proxy HTTPS (Nginx en el host)
# Obligatorio para que Moodle genere URLs https:// correctas
MOODLE_SSLPROXY="${MOODLE_SSLPROXY:-false}"

DB_TYPE="${DB_TYPE:-pgsql}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-moodle}"
DB_USER="${DB_USER:-moodle}"
DB_PASS="${DB_PASS:-moodle}"
DB_PREFIX="${DB_PREFIX:-mdl_}"

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

WWWROOT_DIR="/var/www/html"
CONFIG_FILE="${WWWROOT_DIR}/config.php"

# =============================================================================
# 1. Esperar a que la base de datos esté lista
# =============================================================================
wait_for_db() {
    log "Esperando conexión a base de datos (${DB_HOST}:${DB_PORT})..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if php -r "
            try {
                \$pdo = new PDO(
                    '${DB_TYPE}:host=${DB_HOST};port=${DB_PORT};dbname=${DB_NAME}',
                    '${DB_USER}',
                    '${DB_PASS}'
                );
                exit(0);
            } catch (Exception \$e) {
                exit(1);
            }
        " 2>/dev/null; then
            log_ok "Base de datos disponible."
            return 0
        fi
        attempt=$((attempt + 1))
        log_warn "BD no disponible aún, intento ${attempt}/${max_attempts}..."
        sleep 3
    done

    log_err "No se pudo conectar a la base de datos después de ${max_attempts} intentos."
    exit 1
}

# =============================================================================
# 2. Generar config.php desde variables de entorno
# =============================================================================
generate_config() {
    log "Generando config.php..."

    cat > "${CONFIG_FILE}" << EOF
<?php  // Moodle configuration file — generado automáticamente al arrancar el contenedor
       // Para modificar, edita las variables de entorno en docker-compose.yml o .env

unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

// ─── Base de datos ────────────────────────────────────────────────────────────
\$CFG->dbtype    = '${DB_TYPE}';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = '${DB_HOST}';
\$CFG->dbport    = ${DB_PORT};
\$CFG->dbname    = '${DB_NAME}';
\$CFG->dbuser    = '${DB_USER}';
\$CFG->dbpass    = '${DB_PASS}';
\$CFG->prefix    = '${DB_PREFIX}';
\$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbsocket'  => '',
);

// ─── Rutas ────────────────────────────────────────────────────────────────────
\$CFG->wwwroot   = '${MOODLE_WWWROOT}';
\$CFG->dataroot  = '${MOODLE_DATAROOT}';
\$CFG->admin     = 'admin';

// ─── Reverse proxy / SSL ──────────────────────────────────────────────────────
// IMPORTANTE: Activar cuando Moodle está detrás de un Nginx/proxy que termina SSL.
// Sin esto, Moodle genera URLs http:// aunque el usuario acceda por https://
\$CFG->reverseproxy = ${MOODLE_SSLPROXY} === 'true' ? true : false;
\$CFG->sslproxy     = ${MOODLE_SSLPROXY} === 'true' ? true : false;

// ─── Seguridad ────────────────────────────────────────────────────────────────
\$CFG->directorypermissions = 02777;

// ─── Cache (Redis MUC) ────────────────────────────────────────────────────────
// Habilitado si REDIS_HOST está definido
if (!empty('${REDIS_HOST}')) {
    \$CFG->session_handler_class = '\core\session\redis';
    \$CFG->session_redis_host    = '${REDIS_HOST}';
    \$CFG->session_redis_port    = ${REDIS_PORT};
    \$CFG->session_redis_database = 0;
    \$CFG->session_redis_auth    = '';
    \$CFG->session_redis_prefix  = 'moodle_session_';
    \$CFG->session_redis_acquire_lock_timeout = 120;
    \$CFG->session_redis_lock_expire          = 7200;
}

// ─── Rendimiento ─────────────────────────────────────────────────────────────
\$CFG->pathtophp    = '/usr/local/bin/php';
\$CFG->pathtodu     = '/usr/bin/du';
\$CFG->aspellpath   = '/usr/bin/aspell';

// ─── Debug (desactivar en producción) ────────────────────────────────────────
// \$CFG->debug        = E_ALL;
// \$CFG->debugdisplay = 1;

require_once(__DIR__ . '/lib/setup.php');
EOF

    chown www-data:www-data "${CONFIG_FILE}"
    chmod 640 "${CONFIG_FILE}"
    log_ok "config.php generado."
}

# =============================================================================
# 3. Instalar o actualizar Moodle
# =============================================================================
install_or_upgrade() {
    # Verificar si Moodle ya tiene tablas instaladas
    local is_installed
    is_installed=$(php -r "
        try {
            \$pdo = new PDO(
                '${DB_TYPE}:host=${DB_HOST};port=${DB_PORT};dbname=${DB_NAME}',
                '${DB_USER}', '${DB_PASS}'
            );
            \$stmt = \$pdo->query(\"SELECT COUNT(*) FROM information_schema.tables WHERE table_name = '${DB_PREFIX}config'\");
            echo \$stmt->fetchColumn() > 0 ? 'yes' : 'no';
        } catch (Exception \$e) {
            echo 'no';
        }
    " 2>/dev/null)

    if [ "${is_installed}" = "no" ]; then
        # ── Primera instalación ──────────────────────────────────────────────
        log "Primera instalación detectada. Instalando Moodle..."
        php "${WWWROOT_DIR}/admin/cli/install_database.php" \
            --lang="${MOODLE_LANG}" \
            --adminuser="${MOODLE_ADMIN_USER}" \
            --adminpass="${MOODLE_ADMIN_PASS}" \
            --adminemail="${MOODLE_ADMIN_EMAIL}" \
            --fullname="${MOODLE_SITE_NAME}" \
            --shortname="moodle" \
            --agree-license \
            --non-interactive
        log_ok "Moodle instalado correctamente."
    else
        # ── Upgrade (si hay versión más nueva en los archivos) ───────────────
        log "Moodle ya instalado. Verificando si hay upgrade pendiente..."
        php "${WWWROOT_DIR}/admin/cli/upgrade.php" --non-interactive || {
            log_warn "El upgrade falló o no era necesario — continuando."
        }
    fi
}

# =============================================================================
# 4. Permisos y cron
# =============================================================================
setup_permissions() {
    log "Configurando permisos de moodledata..."
    mkdir -p "${MOODLE_DATAROOT}"
    chown -R www-data:www-data "${MOODLE_DATAROOT}"
    chmod -R 0770 "${MOODLE_DATAROOT}"
    log_ok "Permisos configurados."
}

start_cron() {
    log "Iniciando cron de Moodle..."
    service cron start || log_warn "No se pudo iniciar cron (puede no estar disponible)."
}

# =============================================================================
# MAIN
# =============================================================================
log "======================================================"
log "  Moodle Docker — Arrancando"
log "  Versión: ${MOODLE_VERSION_LABEL:-desconocida}"
log "  URL:     ${MOODLE_WWWROOT}"
log "======================================================"

wait_for_db
generate_config
setup_permissions
install_or_upgrade
start_cron

log_ok "Entrypoint completado — iniciando Apache"
log "======================================================"

# Pasar control a apache2-foreground (o al CMD especificado)
exec "$@"
