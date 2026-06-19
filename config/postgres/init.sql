-- PostgreSQL initialization script
-- Se ejecuta solo la primera vez que se crea el volumen de datos

-- Asegurar extensiones útiles para Moodle
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Configuración de encoding (ya viene de POSTGRES_INITDB_ARGS, pero reforzamos)
-- No es necesario hacer nada más aquí, postgres ya usará UTF8 del initdb
