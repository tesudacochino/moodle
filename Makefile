# =============================================================================
# Makefile — Comandos para gestionar el stack de Moodle
# =============================================================================
# Uso: make <target>
#
# Requiere: docker, docker compose (v2), make
# En Windows: usar Git Bash, WSL o instalar make via choco/scoop
# =============================================================================

# Cargar variables del .env si existe
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Valores por defecto — lee del archivo MOODLE_VERSION si no está en .env
MOODLE_VERSION    ?= $(shell cat MOODLE_VERSION 2>/dev/null | tr -d '[:space:]' || echo "MOODLE_405_STABLE")

COMPOSE           := docker compose
DEPLOY_COMPOSE    := docker compose -f docker-compose.deploy.yml
CONTAINER_MOODLE  := moodle_app
BACKUP_DIR        := ./backups
TIMESTAMP         := $(shell date +%Y%m%d_%H%M%S)

.PHONY: help up down restart build rebuild shell logs status \
        backup restore upgrade purge db-shell info check-env \
        deploy-pull deploy-up deploy-down deploy-restart \
        deploy-logs deploy-status deploy-upgrade deploy-backup deploy-shell

# ─── Ayuda ────────────────────────────────────────────────────────────────────

help: ## Muestra esta ayuda
	@echo ""
	@echo "  Moodle Docker — Comandos disponibles"
	@echo "  ─────────────────────────────────────"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Versión de Moodle activa: \033[33m$(MOODLE_VERSION)\033[0m"
	@echo ""

# ─── Stack ────────────────────────────────────────────────────────────────────

up: check-env ## Levanta el stack completo (build si no existe)
	$(COMPOSE) up -d
	@echo ""
	@echo "  ✅  Moodle disponible en: $(MOODLE_WWWROOT)"
	@echo "  📋  Logs: make logs"
	@echo ""

down: ## Para el stack (conserva los volúmenes)
	$(COMPOSE) down

restart: ## Reinicia los contenedores sin rebuildar
	$(COMPOSE) restart

status: ## Muestra el estado de los contenedores
	@echo ""
	$(COMPOSE) ps
	@echo ""

logs: ## Ver logs en tiempo real (Ctrl+C para salir)
	$(COMPOSE) logs -f --tail=100

logs-moodle: ## Ver solo logs del contenedor Moodle
	$(COMPOSE) logs -f --tail=100 moodle

# ─── Build / Actualización ────────────────────────────────────────────────────

build: check-env ## Build inicial de la imagen
	$(COMPOSE) build

rebuild: check-env ## Rebuild completo sin cache (para actualizar Moodle)
	@echo ""
	@echo "  🔄  Rebuilding con Moodle versión: \033[33m$(MOODLE_VERSION)\033[0m"
	@echo "  ⚠️   Esto descargará el código de Moodle desde GitHub..."
	@echo ""
	$(COMPOSE) build --no-cache --pull moodle
	@echo ""
	@echo "  ✅  Build completado. Ejecuta 'make upgrade' para aplicar la migración de BD."
	@echo ""

# ─── Mantenimiento ────────────────────────────────────────────────────────────

upgrade: ## Ejecuta el upgrade de Moodle en el contenedor corriendo
	@echo ""
	@echo "  🚀  Ejecutando upgrade de Moodle..."
	$(COMPOSE) exec moodle php /var/www/html/admin/cli/upgrade.php --non-interactive
	@echo ""
	@echo "  ✅  Upgrade completado."
	@echo ""

purge: ## Purga todas las caches de Moodle
	$(COMPOSE) exec moodle php /var/www/html/admin/cli/purge_caches.php
	@echo "  ✅  Caches purgadas."

install-plugins: ## Instala los plugins listados en plugins.txt
	$(COMPOSE) exec moodle /usr/local/bin/install-plugins.sh

# ─── Acceso a contenedores ────────────────────────────────────────────────────

shell: ## Shell bash en el contenedor Moodle
	$(COMPOSE) exec moodle bash

shell-db: ## Shell psql en PostgreSQL
	$(COMPOSE) exec db psql -U $(DB_USER) -d $(DB_NAME)

shell-redis: ## Shell redis-cli
	$(COMPOSE) exec redis redis-cli

# ─── Backup / Restore ─────────────────────────────────────────────────────────

backup: ## Hace backup de BD + moodledata → ./backups/
	@mkdir -p $(BACKUP_DIR)
	@echo ""
	@echo "  📦  Backup iniciado: $(TIMESTAMP)"
	@echo "  └─ Exportando base de datos..."
	$(COMPOSE) exec -T db pg_dump \
		-U $(DB_USER) \
		-d $(DB_NAME) \
		--no-password \
		| gzip > $(BACKUP_DIR)/db_$(TIMESTAMP).sql.gz
	@echo "  └─ Backup de BD guardado: $(BACKUP_DIR)/db_$(TIMESTAMP).sql.gz"
	@echo "  └─ Comprimiendo moodledata..."
	$(COMPOSE) exec moodle tar -czf - -C /var/www moodledata \
		> $(BACKUP_DIR)/moodledata_$(TIMESTAMP).tar.gz
	@echo "  └─ moodledata guardado: $(BACKUP_DIR)/moodledata_$(TIMESTAMP).tar.gz"
	@echo ""
	@echo "  ✅  Backup completado en $(BACKUP_DIR)/"
	@echo ""

restore: ## Restaura backup — uso: make restore DB=backups/db_XXX.sql.gz
	@if [ -z "$(DB)" ]; then \
		echo "  ❌  Error: especifica el archivo: make restore DB=backups/db_YYYYMMDD.sql.gz"; \
		exit 1; \
	fi
	@echo "  ⚠️   ATENCIÓN: Esto sobreescribirá la base de datos actual."
	@read -p "  ¿Continuar? [y/N] " ans; [ "$${ans}" = "y" ] || exit 1
	@echo "  └─ Restaurando $(DB)..."
	@zcat $(DB) | $(COMPOSE) exec -T db psql -U $(DB_USER) -d $(DB_NAME)
	@echo "  ✅  Base de datos restaurada."

# ─── Utilidades ───────────────────────────────────────────────────────────────

info: ## Muestra información del entorno actual
	@echo ""
	@echo "  📋  Información del stack Moodle"
	@echo "  ──────────────────────────────────────"
	@echo "  Versión configurada:  $(MOODLE_VERSION)"
	@echo "  URL:                  $(MOODLE_WWWROOT)"
	@echo "  Puerto HTTP:          $(HTTP_PORT)"
	@echo "  Base de datos:        $(DB_NAME) @ db:5432"
	@echo ""
	@$(COMPOSE) exec moodle php /var/www/html/admin/cli/cfg.php --name=version 2>/dev/null \
		&& echo "  (Versión real de Moodle instalada en BD)" || echo "  (Contenedor no corriendo o no instalado)"
	@echo ""

check-env: ## Verifica que existe el archivo .env
	@if [ ! -f .env ]; then \
		echo ""; \
		echo "  ❌  No se encontró el archivo .env"; \
		echo "  └─ Crea uno con: cp .env.example .env"; \
		echo "  └─ Luego edita las contraseñas y variables."; \
		echo ""; \
		exit 1; \
	fi

# ─── Despliegue desde Docker Hub (docker-compose.deploy.yml) ──────────────────

deploy-pull: check-env ## Descarga la imagen desde Docker Hub
	@echo ""
	@echo "  ⤵️   Descargando imagen: $(DOCKERHUB_USERNAME:-molero)/moodle:$(MOODLE_IMAGE_TAG:-latest)"
	$(DEPLOY_COMPOSE) pull moodle
	@echo "  ✅  Imagen descargada."
	@echo ""

deploy-up: check-env ## Levanta el stack de PRODUCCIÓN desde Docker Hub
	$(DEPLOY_COMPOSE) pull moodle
	$(DEPLOY_COMPOSE) up -d
	@echo ""
	@echo "  ✅  Stack de producción en marcha."
	@echo "  📋  Logs: make deploy-logs"
	@echo ""

deploy-down: ## Para el stack de producción (conserva volúmenes)
	$(DEPLOY_COMPOSE) down

deploy-restart: ## Reinicia el stack de producción
	$(DEPLOY_COMPOSE) restart

deploy-status: ## Estado del stack de producción
	@echo ""
	$(DEPLOY_COMPOSE) ps
	@echo ""

deploy-logs: ## Logs en tiempo real del stack de producción
	$(DEPLOY_COMPOSE) logs -f --tail=100

deploy-shell: ## Shell bash en el contenedor Moodle (producción)
	$(DEPLOY_COMPOSE) exec moodle bash

deploy-upgrade: ## Ejecuta upgrade de Moodle en el stack de producción
	@echo "  🚀  Ejecutando upgrade en producción..."
	$(DEPLOY_COMPOSE) exec moodle php /var/www/html/admin/cli/upgrade.php --non-interactive
	@echo "  ✅  Upgrade completado."

deploy-backup: ## Backup de BD + moodledata en el stack de producción
	@mkdir -p $(BACKUP_DIR)
	@echo ""
	@echo "  📦  Backup producción: $(TIMESTAMP)"
	$(DEPLOY_COMPOSE) exec -T db pg_dump \
		-U $(DB_USER) \
		-d $(DB_NAME) \
		--no-password \
		| gzip > $(BACKUP_DIR)/db_deploy_$(TIMESTAMP).sql.gz
	@echo "  └─ BD: $(BACKUP_DIR)/db_deploy_$(TIMESTAMP).sql.gz"
	$(DEPLOY_COMPOSE) exec moodle tar -czf - -C /var/www moodledata \
		> $(BACKUP_DIR)/moodledata_deploy_$(TIMESTAMP).tar.gz
	@echo "  └─ Data: $(BACKUP_DIR)/moodledata_deploy_$(TIMESTAMP).tar.gz"
	@echo "  ✅  Backup completado."
	@echo ""

# ─── Destrucción (peligroso) ──────────────────────────────────────────────────

destroy: ## ⚠️  PELIGROSO: Para y elimina contenedores + volúmenes (pérdida de datos)
	@echo ""
	@echo "  ⚠️   ATENCIÓN: Esto eliminará TODOS los datos de Moodle."
	@read -p "  Escribe 'DESTRUIR' para confirmar: " ans; [ "$${ans}" = "DESTRUIR" ] || exit 1
	$(COMPOSE) down -v --remove-orphans
	@echo "  🗑️   Stack y volúmenes eliminados."
