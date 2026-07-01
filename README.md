# 🎓 Moodle Docker — Imagen personalizada y mantenible (Moodle 5.0)

[![Docker Build](https://github.com/tesudacochino/moodle/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/tesudacochino/moodle/actions/workflows/docker-publish.yml)
[![Docker Hub](https://img.shields.io/docker/v/tesudacochino/moodle?label=Docker%20Hub&logo=docker)](https://hub.docker.com/r/tesudacochino/moodle)

Stack Docker completo para Moodle LMS basado en `moodlehq/moodle-php-apache:8.2`,
con código de Moodle descargado directamente desde GitHub en tiempo de build.

## Servicios

| Servicio | Imagen | Puerto |
|---|---|---|
| **Moodle** (PHP 8.2 + Apache) | `tesudacochino/moodle:<version>` | `8080` |
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
./scripts/update-moodle.sh MOODLE_500_STABLE
```

El script hace backup automático, actualiza la versión, rebuilda y ejecuta la migración de BD.

### Método 2 — Manual paso a paso

```bash
# 1. Backup de seguridad (¡no saltarse este paso!)
make backup

# 2. Cambiar versión en .env
# Edita .env y cambia MOODLE_VERSION=MOODLE_500_STABLE

# 3. Rebuild de la imagen (descarga la nueva versión de GitHub)
make rebuild

# 4. Aplicar upgrade de base de datos
make upgrade
```

### Ramas de Moodle disponibles

| Rama Git | Versión Moodle | Soporte |
|---|---|---|
| `MOODLE_500_STABLE` | 5.0.x | ✅ Última versión |
| `MOODLE_405_STABLE` | 4.5.x | LTS ✅ Recomendada |
| `MOODLE_404_STABLE` | 4.4.x | Activa |
| `MOODLE_403_STABLE` | 4.3.x | Solo seguridad |

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
mod/attendance  https://github.com/danmarsden/moodle-mod_attendance   MOODLE_500_STABLE
theme/moove     https://github.com/willianmano/moodle-theme-moove      MOODLE_500_STABLE
```

---

## ⚙️ Configuración

### Variables de entorno (`.env`)

| Variable | Default | Descripción |
|---|---|---|
| `MOODLE_VERSION` | `MOODLE_500_STABLE` | Rama de Moodle a usar |
| `MOODLE_WWWROOT` | `http://localhost:8080` | URL pública de Moodle |
| `MOODLE_ADMIN_USER` | `admin` | Usuario administrador |
| `MOODLE_ADMIN_PASS` | `Admin1234!` | Contraseña admin |
| `MOODLE_LANG` | `es` | Idioma por defecto |
| `DB_NAME` | `moodle` | Nombre de la BD |
| `DB_USER` | `moodle` | Usuario de BD |
| `DB_PASS` | `moodle` | Contraseña de BD |
| `HTTP_PORT` | `8080` | Puerto HTTP del host |

### 📧 Configuración de Correo (SMTP)

Moodle 5.0 en este stack permite configurar el correo directamente desde variables de entorno. Descomenta y ajusta en tu `.env`:

- `SMTP_HOSTS`: Servidor SMTP (ej: `smtp.gmail.com:587`)
- `SMTP_USER`: Usuario (ej: `tu-correo@gmail.com`)
- `SMTP_PASS`: Contraseña o App Password
- `SMTP_SECURE`: `tls` o `ssl`
- `SMTP_NOREPLY_ADDRESS`: Dirección de remitente para notificaciones

### ⏰ Tareas programadas (Cron)

El cron de Moodle está **integrado en el contenedor**. Se ejecuta cada minuto automáticamente.
Puedes ver el log del cron con:
```bash
docker exec -it moodle tail -f /var/log/moodle-cron.log
```

---

## 💾 Backups

Los backups se guardan en `./backups/` con timestamp:
- `db_YYYYMMDD_HHMMSS.sql.gz` — Volcado de PostgreSQL
- `moodledata_YYYYMMDD_HHMMSS.tar.gz` — Archivos de Moodle

---

## 🔒 Notas de seguridad

- `moodlehq/moodle-php-apache` está pensado para **desarrollo/staging**, no producción.
- Para producción, usa HTTPS (`MOODLE_SSLPROXY=true`) y contraseñas fuertes.
- El archivo `config.php` se genera dinámicamente y hereda las variables del sistema.
- El servicio `cron` inyecta las variables de entorno necesarias desde `/etc/environment`.

---

## 🐛 Troubleshooting

**El cron no envía correos**
Verifica que las variables `SMTP_*` en el `.env` son correctas y reinicia el stack:
```bash
make restart
```

**Permisos de archivos**
Si editas archivos manualmente, asegúrate de que pertenecen a `www-data`:
```bash
docker exec -it moodle chown -R www-data:www-data /var/www/html
```
