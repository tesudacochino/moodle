# 🎓 Moodle Docker — Imagen personalizada y mantenible

[![Docker Build](https://github.com/tesudacochino/moodle/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/tesudacochino/moodle/actions/workflows/docker-publish.yml)
[![Docker Hub](https://img.shields.io/docker/v/tesudacochino/moodle?label=Docker%20Hub&logo=docker)](https://hub.docker.com/r/tesudacochino/moodle)

Stack Docker completo para Moodle LMS basado en `moodlehq/moodle-php-apache:8.4`,
con código de Moodle descargado directamente desde GitHub en tiempo de build.

## Servicios

| Servicio | Imagen | Puerto |
|---|---|---|
| **Moodle** (PHP 8.4 + Apache) | `tesudacochino/moodle:<version>` | `8080` |
| **PostgreSQL 17** | `postgres:17-alpine` | interno |
| **Redis 7** | `redis:7-alpine` | interno |

---

## 🚀 Inicio rápido

### 1. Clonar y configurar

```bash
# Copiar y editar el archivo de configuración
cp .env.example .env
```

Edita `.env` y cambia al menos:
- `MOODLE_ADMIN_PASS` — contraseña del admin
- `DB_PASS` — contraseña de PostgreSQL
- `MOODLE_WWWROOT` — URL de acceso (si no es localhost)

### 2. Build y arranque

```bash
make build   # Build de la imagen (descarga Moodle desde GitHub, ~5 min)
make up      # Levanta el stack completo
make logs    # Ver el progreso de instalación
```

La primera vez Moodle instala la base de datos automáticamente.
Accede en: **http://localhost:8080**

---

## 📋 Comandos disponibles

```bash
make help          # Ver todos los comandos con descripción
make up            # Levantar el stack
make down          # Parar el stack
make restart       # Reiniciar contenedores
make status        # Estado de los contenedores
make logs          # Logs en tiempo real
make shell         # Bash en el contenedor Moodle
make shell-db      # psql en PostgreSQL
make backup        # Backup de BD + moodledata → ./backups/
make restore DB=backups/db_XXX.sql.gz   # Restaurar backup
make purge         # Purgar caches de Moodle
make info          # Info del entorno
```

---

## 🔄 Actualizar Moodle

### Método 1 — Script interactivo (recomendado)

```bash
./scripts/update-moodle.sh MOODLE_405_STABLE
```

El script hace backup automático, actualiza la versión, rebuilda y ejecuta la migración de BD.

### Método 2 — Manual paso a paso

```bash
# 1. Backup de seguridad (¡no saltarse este paso!)
make backup

# 2. Cambiar versión en .env
# Edita .env y cambia MOODLE_VERSION=MOODLE_405_STABLE

# 3. Rebuild de la imagen (descarga la nueva versión de GitHub)
make rebuild

# 4. Aplicar upgrade de base de datos
make upgrade
```

### Ramas de Moodle disponibles

| Rama Git | Versión Moodle | Soporte |
|---|---|---|
| `MOODLE_405_STABLE` | 4.5.x | LTS ✅ Recomendada |
| `MOODLE_404_STABLE` | 4.4.x | Activa |
| `MOODLE_403_STABLE` | 4.3.x | Solo seguridad |
| `MOODLE_401_STABLE` | 4.1.x | LTS |

---

## 🧩 Plugins de terceros

Añade plugins a `plugins.txt` y ejecuta:

```bash
make install-plugins
make upgrade   # Para registrar los nuevos plugins en la BD
```

Formato de `plugins.txt`:
```
# tipo/nombre   url_repositorio   rama
mod/attendance  https://github.com/danmarsden/moodle-mod_attendance   MOODLE_405_STABLE
theme/moove     https://github.com/willianmano/moodle-theme-moove      MOODLE_405_STABLE
```

---

## ⚙️ Configuración

### Variables de entorno (`.env`)

| Variable | Default | Descripción |
|---|---|---|
| `MOODLE_VERSION` | `MOODLE_405_STABLE` | Rama de Moodle a usar |
| `MOODLE_WWWROOT` | `http://localhost:8080` | URL pública de Moodle |
| `MOODLE_ADMIN_USER` | `admin` | Usuario administrador |
| `MOODLE_ADMIN_PASS` | `Admin1234!` | Contraseña admin |
| `MOODLE_LANG` | `es` | Idioma por defecto |
| `DB_NAME` | `moodle` | Nombre de la BD |
| `DB_USER` | `moodle` | Usuario de BD |
| `DB_PASS` | `moodle` | Contraseña de BD |
| `HTTP_PORT` | `8080` | Puerto HTTP del host |

### Ajustes PHP (`config/php/custom.ini`)

Modifica límites de subida, memoria, etc. Reinicia el contenedor para aplicar:
```bash
make restart
```

---

## 💾 Backups

Los backups se guardan en `./backups/` con timestamp:
- `db_YYYYMMDD_HHMMSS.sql.gz` — Volcado de PostgreSQL
- `moodledata_YYYYMMDD_HHMMSS.tar.gz` — Archivos de Moodle

> ⚠️ **Nunca elimines** los volúmenes Docker `moodledata` y `db_data` sin antes hacer backup.

---

## 🗂️ Estructura del proyecto

```
.
├── Dockerfile                    # Imagen principal (versión configurable via ARG)
├── docker-compose.yml            # Stack: Moodle + PostgreSQL + Redis
├── .env.example                  # Plantilla de configuración
├── Makefile                      # Comandos de gestión
├── plugins.txt                   # Lista de plugins de terceros
├── config/
│   ├── php/custom.ini            # PHP settings (uploads, memory, opcache)
│   ├── apache/moodle.conf        # VirtualHost Apache
│   └── postgres/init.sql         # SQL de inicialización de PostgreSQL
├── scripts/
│   ├── entrypoint.sh             # Entrypoint: genera config.php, instala/actualiza
│   ├── update-moodle.sh          # Script de actualización guiado
│   └── install-plugins.sh        # Instalador de plugins
└── data/                         # Ignorado por git — contenido en volumen Docker
```

---

## 🔒 Notas de seguridad

- `moodlehq/moodle-php-apache` está pensado para **desarrollo/staging**, no producción
- Para producción, cambia la contraseña del admin y de la BD en `.env`
- El archivo `config.php` se genera dinámicamente — nunca se commitea a git
- Redis usa `allkeys-lru` con 256MB de límite — ajusta en `docker-compose.yml`

---

## 🐛 Troubleshooting

**El contenedor Moodle se reinicia continuamente**
```bash
make logs-moodle   # Ver el error específico
```

**Error de conexión a la BD**
```bash
make shell-db      # Verificar que PostgreSQL funciona
```

**Moodle muestra página en blanco**
```bash
make shell
tail -f /var/log/apache2/moodle_error.log
```

**Forzar reinstalación limpia** (⚠️ pierde todos los datos)
```bash
make destroy
make backup  # ¡Primero hacer backup si tienes datos!
```
