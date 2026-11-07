-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- consultas/delete.sql — Etapa 5 · Borrados (D1–D6)
--
-- Cada consigna lleva: código, enunciado, estrategia y los triggers o
-- constraints que se disparan. Todas se prueban en transacción
-- (BEGIN ... ROLLBACK) mostrando el estado antes y después, de modo que
-- la base queda intacta al terminar el archivo.
--
-- Requisito: base cargada con db/seed/seed.py (semilla 42) y migraciones
-- 001–008 aplicadas. Las fechas son relativas a CURRENT_DATE.
-- =====================================================================

\pset pager off
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Parámetros de ejecución (obligatorios). NO están hardcodeados en este
-- archivo: la consigna habla de "una localidad determinada/específica",
-- así que el valor se elige en runtime según el dataset cargado.
--
--   psql -v localidad_d3="Chacras de Coria" -v localidad_d6="General Alvear" \
--        -f consultas/delete.sql
--
-- Se usan abajo como :'localidad_d3' y :'localidad_d6' (literal entre comillas).
-- ---------------------------------------------------------------------
\if :{?localidad_d3} \else
  \echo 'ERROR: falta el parámetro localidad_d3 (ejecutá con -v localidad_d3="..." -f consultas/delete.sql)'
  \quit
\endif
\if :{?localidad_d6} \else
  \echo 'ERROR: falta el parámetro localidad_d6 (ejecutá con -v localidad_d6="..." -f consultas/delete.sql)'
  \quit
\endif

-- =====================================================================
-- D1 · Borrar los comprobantes con más de 5 años de socios del club
--
-- Estrategia: se filtran los comprobantes por fecha y por el tipo de su
-- cliente (socio). La FK renglon_comprobante.nro -> comprobante está con
-- ON DELETE CASCADE, así que los renglones se van solos.
--
-- Triggers/constraints que se disparan:
--   · trg_renglon_comprobante_bud (RN-08/RN-12): en el borrado en cascada
--     detecta que la cabecera ya no existe y deja pasar el DELETE.
--   · El stock NO se devuelve: no hay trigger AFTER DELETE que lo reponga.
--     Es una decisión documentada (anular una venta no restaura el stock).
-- =====================================================================
\echo '=== D1: comprobantes de socios con más de 5 años ==='
BEGIN;

SELECT count(*) AS comprobantes_antes
FROM comprobante c
JOIN cliente cl ON cl.id_cliente = c.id_cliente
WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years';

DELETE FROM comprobante
WHERE fecha < CURRENT_DATE - INTERVAL '5 years'
  AND id_cliente IN (SELECT id_cliente FROM cliente WHERE tipo = 'socio');

SELECT count(*) AS comprobantes_despues
FROM comprobante c
JOIN cliente cl ON cl.id_cliente = c.id_cliente
WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years';

ROLLBACK;

-- =====================================================================
-- D2 · Eliminar las cepas que no componen ningún vino ni están plantadas
--
-- Estrategia: doble anti-join (NOT EXISTS) contra composicion y parcela.
-- Son las cepas "sin uso" del catálogo (Petit Verdot, Cabernet Franc,
-- Viognier), que el seed carga a propósito para probar esta consulta.
--
-- Triggers/constraints que se disparan:
--   · composicion.id_cepa -> cepa  ON DELETE RESTRICT
--   · parcela.id_cepa     -> cepa  ON DELETE RESTRICT
--     Por eso solo se pueden borrar las cepas sin filas en esas tablas.
-- =====================================================================
\echo '=== D2: cepas sin composición ni parcela ==='
BEGIN;

SELECT count(*) AS cepas_a_borrar
FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
  AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

DELETE FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
  AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

SELECT count(*) AS cepas_sin_uso_restantes
FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
  AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

ROLLBACK;

-- =====================================================================
-- D3 · La sala de una localidad dada fue dada de baja: eliminar los
--      empleados de esa sala que trabajaron menos de dos años
--
-- Estrategia: se resuelve la localidad elegida (parámetro :localidad_d3) y se
-- toma UNA sala de ella (en este seed la localidad tiene una sola sala). Se
-- filtra por antigüedad (< 2 años) y se EXCLUYE al encargado, porque
-- localidad.cuit_encargado -> empleado está con ON DELETE RESTRICT.
--
-- Triggers/constraints que se disparan:
--   · localidad.cuit_encargado -> empleado ON DELETE RESTRICT: si el
--     empleado es encargado regional, el borrado se rechaza. Por eso la
--     consulta lo descarta con NOT EXISTS.
-- =====================================================================
\echo '=== D3: empleados con <2 años de la sala dada de baja ==='
BEGIN;

SELECT count(*) AS empleados_antes
FROM empleado e
WHERE e.id_sala = (
        SELECT s.id_sala FROM sala_venta s
        WHERE s.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d3')
      )
  AND e.fecha_ingreso > CURRENT_DATE - INTERVAL '2 years'
  AND NOT EXISTS (SELECT 1 FROM localidad l WHERE l.cuit_encargado = e.cuit);

DELETE FROM empleado e
WHERE e.id_sala = (
        SELECT s.id_sala FROM sala_venta s
        WHERE s.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d3')
      )
  AND e.fecha_ingreso > CURRENT_DATE - INTERVAL '2 years'
  AND NOT EXISTS (SELECT 1 FROM localidad l WHERE l.cuit_encargado = e.cuit);

SELECT count(*) AS empleados_despues
FROM empleado e
WHERE e.id_sala = (
        SELECT s.id_sala FROM sala_venta s
        WHERE s.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d3')
      )
  AND e.fecha_ingreso > CURRENT_DATE - INTERVAL '2 years'
  AND NOT EXISTS (SELECT 1 FROM localidad l WHERE l.cuit_encargado = e.cuit);

ROLLBACK;

-- =====================================================================
-- D4 · Borrar los socios que nunca compraron y se dieron de alta hace
--      más de 5 años
--
-- Estrategia: anti-join (NOT EXISTS) contra comprobante + filtro por
-- fecha_alta. Es la condición que se midió en la Etapa 4
-- (docs/entregables/etapa 4/consultas_medicion.sql), aquí convertida en
-- DELETE.
--
-- Triggers/constraints que se disparan:
--   · socio.id_cliente -> cliente ON DELETE CASCADE: al borrar el cliente
--     se elimina su fila de subtipo.
--   · comprobante.id_cliente -> cliente ON DELETE RESTRICT: por eso el
--     NOT EXISTS es imprescindible; un socio con compras no se borra.
-- =====================================================================
\echo '=== D4: socios sin compras con alta >5 años ==='
BEGIN;

SELECT count(*) AS socios_antes
FROM cliente c
WHERE c.tipo = 'socio'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

DELETE FROM cliente c
WHERE c.tipo = 'socio'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

SELECT count(*) AS socios_despues
FROM cliente c
WHERE c.tipo = 'socio'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

ROLLBACK;

-- =====================================================================
-- D5 · Eliminar los ingresos en estado procesado de hace más de 365 días
--
-- Estrategia: filtro por estado = 'procesado' y por fecha. La FK
-- renglon_ingreso.cod_ingreso -> ingreso está con ON DELETE CASCADE.
--
-- Triggers/constraints que se disparan:
--   · trg_renglon_ingreso_doc (RN-12): en el borrado en cascada detecta
--     que la cabecera ya no existe y deja pasar el DELETE.
--   · El stock del depósito NO se revierte: al borrar un ingreso ya
--     procesado no hay trigger que descuente el stock.
-- =====================================================================
\echo '=== D5: ingresos procesados con más de 365 días ==='
BEGIN;

SELECT count(*) AS ingresos_antes
FROM ingreso
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - INTERVAL '365 days';

DELETE FROM ingreso
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - INTERVAL '365 days';

SELECT count(*) AS ingresos_despues
FROM ingreso
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - INTERVAL '365 days';

ROLLBACK;

-- =====================================================================
-- D6 · Borrar los socios sin compras que viven en una localidad específica
--
-- Estrategia: igual que D4 (anti-join contra comprobante), pero filtrado
-- por la localidad elegida (parámetro :localidad_d6).
--
-- Triggers/constraints que se disparan:
--   · socio.id_cliente -> cliente ON DELETE CASCADE.
--   · comprobante.id_cliente -> cliente ON DELETE RESTRICT (por el NOT EXISTS).
--   · cliente.id_localidad -> localidad ON DELETE RESTRICT: no bloquea,
--     porque se borran clientes, no localidades.
-- =====================================================================
\echo '=== D6: socios sin compras de la localidad elegida ==='
BEGIN;

SELECT count(*) AS socios_antes
FROM cliente c
WHERE c.tipo = 'socio'
  AND c.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d6')
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

DELETE FROM cliente c
WHERE c.tipo = 'socio'
  AND c.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d6')
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

SELECT count(*) AS socios_despues
FROM cliente c
WHERE c.tipo = 'socio'
  AND c.id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_d6')
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

ROLLBACK;
