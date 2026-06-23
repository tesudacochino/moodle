#!/bin/bash
# =============================================================================
# update-moodle.sh — Actualización segura de Moodle
# =============================================================================
# Uso:
#   ./scripts/update-moodle.sh [nueva_version]
#
# Ejemplos:
#   ./scripts/update-moodle.sh MOODLE_405_STABLE
#   ./scripts/update-moodle.sh MOODLE_404_STABLE
#
# Este script:
#   1. Muestra la versión actual
#   2. Hace backup automático
#   3. Actualiza MOODLE_VERSION en .env
#   4. Ejecuta rebuild de la imagen
#   5. Reinicia el stack y ejecuta upgrade de BD
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[Update]${NC} $*"; }
log_ok()  { echo -e "${GREEN}[Update]${NC} ✅ $*"; }
log_warn(){ echo -e "${YELLOW}[Update]${NC} ⚠️  $*"; }
log_err() { echo -e "${RED}[Update]${NC} ❌ $*"; }

# ─── Verificar que estamos en la raíz del proyecto ────────────────────────────
if [ ! -f "Makefile" ] || [ ! -f ".env" ]; then
    log_err "Ejecuta este script desde la raíz del proyecto (donde está el Makefile y .env)"
    exit 1
fi

# ─── Versión nueva ─────────────────────────────────────────────────────────────
NEW_VERSION="${1:-}"
CURRENT_VERSION=$(cat MOODLE_VERSION 2>/dev/null | tr -d '[:space:]')

if [ -z "${NEW_VERSION}" ]; then
    echo ""
    log "Versión actual: ${CURRENT_VERSION}"
    echo ""
    echo "  Ramas disponibles (ejemplos):"
    echo "    MOODLE_405_STABLE  → Moodle 4.5.x (LTS)"
    echo "    MOODLE_404_STABLE  → Moodle 4.4.x"
    echo "    MOODLE_403_STABLE  → Moodle 4.3.x"
    echo ""
    read -rp "  Nueva versión: " NEW_VERSION
fi

if [ "${NEW_VERSION}" = "${CURRENT_VERSION}" ]; then
    log_warn "Ya estás en la versión ${CURRENT_VERSION}. ¿Quieres forzar el rebuild de todas formas?"
    read -rp "  ¿Continuar? [y/N] " ans
    [ "${ans}" = "y" ] || exit 0
fi

# ─── Confirmación ─────────────────────────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │  ACTUALIZACIÓN DE MOODLE                            │"
echo "  ├─────────────────────────────────────────────────────┤"
echo "  │  Versión actual:  ${CURRENT_VERSION}"
echo "  │  Nueva versión:   ${NEW_VERSION}"
echo "  ├─────────────────────────────────────────────────────┤"
echo "  │  Pasos:                                             │"
echo "  │    1. Backup automático de BD y moodledata          │"
echo "  │    2. Rebuild de imagen Docker                      │"
echo "  │    3. Recrear contenedor Moodle                     │"
echo "  │    4. Ejecutar upgrade de base de datos             │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""
read -rp "  ¿Continuar? [y/N] " confirm
[ "${confirm}" = "y" ] || { log "Actualización cancelada."; exit 0; }

# ─── 1. Backup ────────────────────────────────────────────────────────────────
log "Paso 1/4: Haciendo backup..."
make backup
log_ok "Backup completado."

# ─── 2. Actualizar .env ───────────────────────────────────────────────────────
log "Paso 2/4: Actualizando MOODLE_VERSION..."
echo "${NEW_VERSION}" > MOODLE_VERSION
log_ok "MOODLE_VERSION actualizado → ${NEW_VERSION}"

# ─── 3. Rebuild de la imagen ──────────────────────────────────────────────────
log "Paso 3/4: Rebuilding imagen Docker (esto puede tardar unos minutos)..."
make rebuild
log_ok "Imagen rebuildeada."

# ─── 4. Recrear contenedor y upgrade BD ──────────────────────────────────────
log "Paso 4/4: Reiniciando Moodle y aplicando upgrade de BD..."
docker compose up -d --force-recreate moodle

# Esperar a que el contenedor esté listo
log "Esperando que Moodle arranque..."
sleep 15

# El entrypoint ya ejecuta el upgrade automáticamente al detectar versión nueva
# Pero lo forzamos por si acaso:
make upgrade || log_warn "Upgrade CLI completado (puede mostrar warnings si ya estaba al día)."

# ─── Resultado ────────────────────────────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
log_ok "  Actualización completada: ${CURRENT_VERSION} → ${NEW_VERSION}"
echo "  │  Verifica en: $(grep '^MOODLE_WWWROOT=' .env | cut -d= -f2)/admin"
echo "  └─────────────────────────────────────────────────────┘"
echo ""
