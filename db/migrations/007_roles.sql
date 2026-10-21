-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/007_roles.sql
-- Etapa 2: Definición de roles y privilegios mínimos (PostgreSQL 14+)
--
-- Contenido:
--   1. Creación de roles `app_rw` (lectura/escritura para la API) y `reportes_ro` (solo lectura).
--   2. Revocación de permisos públicos en el esquema `public`.
--   3. Asignación de privilegios mínimos (USAGE, SELECT, INSERT, UPDATE, DELETE, EXECUTE).
--   4. Configuración de privilegios por defecto para objetos futuros.
-- =====================================================================

BEGIN;

-- 1. Crear roles si no existen
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_rw') THEN
        -- Nota: La contraseña se configura por entorno o rol externo (Nunca commiteada).
        CREATE ROLE app_rw LOGIN;
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'reportes_ro') THEN
        CREATE ROLE reportes_ro LOGIN;
    END IF;
END
$$;

-- 2. Restringir acceso público al esquema public
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_rw, reportes_ro;

-- 3. Privilegios para app_rw (Lectura y Escritura para la API)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
-- Revocar UPDATE general sobre ingreso y transferencia y otorgar solo sobre columnas permitidas (incluyendo estado para RN-10/11)
REVOKE UPDATE ON ingreso, transferencia FROM app_rw;
GRANT UPDATE (fecha, cod_transportista, cuit_bodega, estado) ON ingreso TO app_rw;
GRANT UPDATE (id_sala, fecha_confeccion, estado) ON transferencia TO app_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_rw;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO app_rw;

-- 4. Privilegios para reportes_ro (Solo lectura para reportes y tableros)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO reportes_ro;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO reportes_ro;

-- 5. Privilegios por defecto para tablas, secuencias y rutinas futuras
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT USAGE, SELECT ON SEQUENCES TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT EXECUTE ON FUNCTIONS TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT EXECUTE ON ROUTINES TO app_rw;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT ON TABLES TO reportes_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT EXECUTE ON FUNCTIONS TO reportes_ro;

COMMIT;
