#!/bin/bash
# =============================================================================
# install-plugins.sh — Instalación automatizada de plugins de Moodle
# =============================================================================
# Lee plugins.txt y descarga/instala cada plugin en el directorio correcto
#
# Formato de plugins.txt:
#   # Comentario
#   <tipo>/<nombre>  <url_git_o_moodle_org_id>  [rama]
#
# Ejemplos en plugins.txt:
#   mod/attendance    https://github.com/danmarsden/moodle-mod_attendance   MOODLE_405_STABLE
#   theme/boost_uni   https://github.com/university/boost_uni               main
#
# =============================================================================
set -euo pipefail

PLUGINS_FILE="/tmp/plugins.txt"
WWWROOT="/var/www/html"

if [ ! -f "${PLUGINS_FILE}" ]; then
    echo "No se encontró plugins.txt. Nada que instalar."
    exit 0
fi

echo "Instalando plugins desde plugins.txt..."

while IFS= read -r line; do
    # Ignorar comentarios y líneas vacías
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    read -r plugin_path plugin_url plugin_branch <<< "$line"
    plugin_branch="${plugin_branch:-main}"
    plugin_dir="${WWWROOT}/${plugin_path}"

    echo "→ Instalando: ${plugin_path} desde ${plugin_url} (rama: ${plugin_branch})"

    if [ -d "${plugin_dir}" ]; then
        echo "  └─ Ya existe, actualizando..."
        git -C "${plugin_dir}" pull origin "${plugin_branch}" || \
            echo "  └─ ⚠️  No se pudo actualizar ${plugin_path}"
    else
        mkdir -p "$(dirname "${plugin_dir}")"
        git clone \
            --depth 1 \
            --branch "${plugin_branch}" \
            "${plugin_url}" \
            "${plugin_dir}" || \
            echo "  └─ ⚠️  No se pudo clonar ${plugin_path}"
    fi

    chown -R www-data:www-data "${plugin_dir}" 2>/dev/null || true

done < "${PLUGINS_FILE}"

echo ""
echo "✅ Plugins instalados. Ejecuta 'php admin/cli/upgrade.php' para activarlos."
