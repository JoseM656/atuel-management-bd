-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- docs/entregables/etapa 4/caso_sin_uso_indice.sql
-- Etapa 4: caso en que el planificador no usa un índice existente (#33)
--
-- Requisito: base cargada con 008_indices.sql aplicado.
-- Se usa idx_comprobante_sala_fecha, cuya primera columna es id_sala.
-- =====================================================================

\pset pager off

-- ---------------------------------------------------------------------
-- A. Filtro poco selectivo: 30 de las 36 salas.
-- El índice existe, pero la consulta necesita la mayoría de las filas.
-- ---------------------------------------------------------------------
\echo '=== A ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), SUM(total)
FROM comprobante
WHERE id_sala BETWEEN 1 AND 30;

-- ---------------------------------------------------------------------
-- B. La misma consulta, desalentando el recorrido secuencial, para medir
-- qué habría pasado si el planificador hubiera usado el índice.
-- SET LOCAL limita el cambio a esta transacción.
-- ---------------------------------------------------------------------
\echo '=== B ==='
BEGIN;
SET LOCAL enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), SUM(total)
FROM comprobante
WHERE id_sala BETWEEN 1 AND 30;
ROLLBACK;

-- ---------------------------------------------------------------------
-- C. Filtro selectivo sobre la misma columna: una sola sala.
-- Con el mismo índice y la misma tabla, solo cambia cuántas filas se piden.
-- ---------------------------------------------------------------------
\echo '=== C ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), SUM(total)
FROM comprobante
WHERE id_sala = 12;
