-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/007_roles.sql
-- Etapa 2: Definición de roles y privilegios mínimos (PostgreSQL 14+)
--
-- Contenido:
--   1. Tres roles: `propietario` (dueño), `app_rw` (API) y `reportes_ro` (reportes).
--   2. Transferencia de ownership del esquema y sus objetos a `propietario`.
--   3. Revocación de permisos públicos en el esquema `public`.
--   4. Privilegios mínimos por rol (USAGE, SELECT, INSERT, UPDATE, DELETE, EXECUTE).
--   5. Privilegios por defecto para objetos futuros.
--
-- Nota RN-10/RN-11: la API (app_rw) NO recibe UPDATE sobre la columna
-- `estado` de ingreso/transferencia; el paso de estado se hace vía los
-- procedimientos sp_terminar_* / sp_procesar_* (SECURITY DEFINER, 004),
-- que corren con los privilegios del propietario.
-- =====================================================================

BEGIN;

-- 1. Crear roles si no existen
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'propietario') THEN
        -- Dueño del esquema y de las rutinas SECURITY DEFINER (no LOGIN).
        CREATE ROLE propietario;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_rw') THEN
        -- Nota: La contraseña se configura por entorno o rol externo (Nunca commiteada).
        CREATE ROLE app_rw LOGIN;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'reportes_ro') THEN
        CREATE ROLE reportes_ro LOGIN;
    END IF;
END
$$;

-- 2. Transferir ownership a `propietario`
--    Así las rutinas SECURITY DEFINER corren con privilegios del propietario
--    (dueño del esquema), no con los del superusuario que aplicó la migración.
ALTER SCHEMA public OWNER TO propietario;

DO $$
DECLARE r RECORD;
BEGIN
    -- Las secuencias IDENTITY no se pueden re-ownear por separado (siguen a su
    -- tabla), así que acá solo se transfieren tablas y vistas.
    FOR r IN
        SELECT c.relname, c.relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p', 'v', 'm')
    LOOP
        EXECUTE format('ALTER %s public.%I OWNER TO propietario',
            CASE r.relkind
                WHEN 'v' THEN 'VIEW'
                WHEN 'm' THEN 'MATERIALIZED VIEW'
                ELSE 'TABLE'
            END,
            r.relname);
    END LOOP;
END $$;

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
    LOOP
        EXECUTE format('ALTER ROUTINE public.%I(%s) OWNER TO propietario',
            r.proname, r.args);
    END LOOP;
END $$;

-- 3. Restringir acceso público al esquema public
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_rw, reportes_ro;

-- 4. Privilegios para app_rw (Lectura y Escritura para la API)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;

-- La API no toca `estado` ni `fecha_confeccion` (inmutable por trigger, RN-11):
-- el flujo RN-10/RN-11 va por sp_terminar_* / sp_procesar_* (SECURITY DEFINER).
REVOKE UPDATE ON ingreso, transferencia FROM app_rw;
GRANT UPDATE (fecha, cod_transportista, cuit_bodega) ON ingreso TO app_rw;
GRANT UPDATE (id_sala) ON transferencia TO app_rw;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_rw;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO app_rw;

-- 5. Privilegios para reportes_ro (Solo lectura para reportes y tableros)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO reportes_ro;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO reportes_ro;

-- 6. Privilegios por defecto para tablas, secuencias y rutinas futuras
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
