-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/tests/db_tests_roles.sql
-- Pruebas del modelo de roles (propietario / app_rw / reportes_ro).
--
-- Verifica que la API (app_rw):
--   * NO puede cambiar la columna estado de ingreso/transferencia por UPDATE
--     directo (RN-10/RN-11 protegidos por privilegio, no por la marca GUC).
--   * SÍ puede terminar y procesar documentos vía sp_terminar_* / sp_procesar_*
--     (SECURITY DEFINER).
--   * reportes_ro es de solo lectura.
--
-- Requiere: migraciones 001..007 aplicadas y base sin datos previos.
-- Corre en una única transacción que termina en ROLLBACK (no deja datos).
-- =====================================================================

\set ON_ERROR_STOP off
\pset footer off

BEGIN;

-- Fixture (mismo criterio que db_tests.sql: sin IDs explícitos)
INSERT INTO departamento (nombre, provincia) VALUES ('San Rafael', 'Mendoza');
INSERT INTO localidad (nombre, provincia, codigo_postal, cuit_encargado) VALUES
  ('San Rafael', 'Mendoza', '5600', '20111111111');
INSERT INTO deposito (id_localidad) VALUES (1);
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES ('Av. Mitre', 100, 'lunes', 1);
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala) VALUES ('20111111111', 'Ana', '2020-01-01', 100, 1);
INSERT INTO cepa (nombre, tipo) VALUES ('Malbec', 'tinta');
INSERT INTO maridaje (nombre, temperatura_servicio) VALUES ('Carnes', 17);
INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30111111111', 'Bodega Uno', 'Calle 1');
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES ('Malbec', 'tinto', 2021, 750, 14, 1000, '30111111111');
INSERT INTO composicion (cod_vino, id_cepa, porcentaje) SELECT cod_vino, 1, 100 FROM vino WHERE nombre = 'Malbec';
INSERT INTO vino_maridaje (cod_vino, id_maridaje) SELECT cod_vino, 1 FROM vino WHERE nombre = 'Malbec';
INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio) VALUES ('Trans', '30333333333', 'a@b.c', '1', 'D');
INSERT INTO transportista_localidad (cod_transportista, id_localidad) VALUES (1, 1);
INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (1, 100);
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, 1, 5);
INSERT INTO ingreso (cod_transportista, cuit_bodega) VALUES (1, '30111111111'), (1, '30111111111');
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (1, 1, 10), (2, 1, 10);
UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = 2;
INSERT INTO transferencia (id_sala) VALUES (1), (1);
INSERT INTO renglon_transferencia (nro, cod_vino, cantidad) VALUES (1, 1, 2), (2, 1, 2);
UPDATE transferencia SET estado = 'terminado' WHERE nro = 2;

-- Helpers: corren una operación como un rol dado y reportan OK/FALLA.
CREATE FUNCTION pg_temp.rol_debe_fallar(t text, r name, s text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE 'SET ROLE ' || quote_ident(r);
  BEGIN
    EXECUTE s;
    v := 'FALLA  ' || t || ' -> la base lo permitió';
  EXCEPTION WHEN insufficient_privilege THEN
    v := 'OK     ' || t || ' -> permission denied';
  WHEN OTHERS THEN
    v := 'ERROR  ' || t || ' -> [' || SQLSTATE || '] ' || SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.rol_debe_funcionar(t text, r name, s text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE 'SET ROLE ' || quote_ident(r);
  BEGIN
    EXECUTE s;
    v := 'OK     ' || t;
  EXCEPTION WHEN OTHERS THEN
    v := 'FALLA  ' || t || ' -> [' || SQLSTATE || '] ' || SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  RETURN v;
END $$;

CREATE TEMP TABLE resultado (n serial, r text);

INSERT INTO resultado (r) VALUES
-- app_rw NO puede tocar estado por UPDATE directo
(pg_temp.rol_debe_fallar('app_rw UPDATE estado ingreso', 'app_rw', $q$UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 2$q$)),
(pg_temp.rol_debe_fallar('app_rw UPDATE estado transferencia', 'app_rw', $q$UPDATE transferencia SET estado = 'procesado' WHERE nro = 2$q$)),
-- ... ni activando la marca GUC (el privilegio es la barrera real)
(pg_temp.rol_debe_fallar('app_rw no se salta el guard con atuel.procesando', 'app_rw',
   $q$DO $d$ BEGIN PERFORM set_config('atuel.procesando','on',true); UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 2; END $d$$q$)),
-- app_rw SÍ puede terminar y procesar vía procedimientos (SECURITY DEFINER)
(pg_temp.rol_debe_funcionar('app_rw termina ingreso vía sp', 'app_rw', $q$CALL sp_terminar_ingreso(1)$q$)),
(pg_temp.rol_debe_funcionar('app_rw procesa ingreso vía sp', 'app_rw', $q$CALL sp_procesar_ingreso(2)$q$)),
(pg_temp.rol_debe_funcionar('app_rw termina transferencia vía sp', 'app_rw', $q$CALL sp_terminar_transferencia(1)$q$)),
(pg_temp.rol_debe_funcionar('app_rw procesa transferencia vía sp', 'app_rw', $q$CALL sp_procesar_transferencia(2)$q$)),
-- reportes_ro solo lectura
(pg_temp.rol_debe_fallar('reportes_ro no inserta', 'reportes_ro', $q$INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30999999999','X','Y')$q$)),
(pg_temp.rol_debe_funcionar('reportes_ro lee', 'reportes_ro', $q$SELECT count(*) FROM vino$q$));

SELECT r AS resultado FROM resultado ORDER BY n;

ROLLBACK;
