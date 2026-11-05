-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/008_indices.sql
-- Etapa 4: índices diseñados a partir de los planes de ejecución
--
-- Contenido: 5 índices, cada uno respaldado por una consulta medida con
-- EXPLAIN (ANALYZE, BUFFERS). Las mediciones y los índices descartados
-- están en docs/entregables/etapa 4/informe_etapa4.md.
--
-- Ownership: un índice siempre pertenece al dueño de su tabla, así que
-- esta migración no necesita transferirlo a propietario.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Índice compuesto. Consulta: S3 (sala y última semana).
-- Sin índice se leen las 150.000 filas de comprobante para conservar menos del 1 %.
-- Orden de columnas: primero id_sala, comparada por igualdad, y después
-- fecha, comparada por rango. Así el índice llega a una sola sala y recorre
-- solo su tramo de fechas; al revés recorrería todas las salas de esas fechas.
-- ---------------------------------------------------------------------
CREATE INDEX idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha);

-- ---------------------------------------------------------------------
-- 2. Índice sobre clave foránea. Consulta: condición de D4 (socios sin
-- compras). PostgreSQL no indexa las FK automáticamente: sin este índice,
-- saber si un cliente compró obliga a recorrer comprobante.
-- ---------------------------------------------------------------------
CREATE INDEX idx_comprobante_cliente
    ON comprobante (id_cliente);

-- ---------------------------------------------------------------------
-- 3. Índice parcial. Consulta: S5 (transferencias pendientes por sala).
-- Solo guarda las filas no procesadas, 150 de 2.500. Sigue siendo chico
-- aunque el historial crezca, porque las transferencias procesadas salen
-- del índice.
-- ---------------------------------------------------------------------
CREATE INDEX idx_transferencia_pendientes
    ON transferencia (id_sala)
    WHERE estado <> 'procesado';

-- ---------------------------------------------------------------------
-- 4. Variante con INCLUDE. Consulta: S4 (un vino en los últimos 15 días).
-- La PK (nro, cod_vino) no sirve para buscar por cod_vino, porque esa no es
-- su primera columna. INCLUDE agrega las otras columnas que usa S4, y la
-- base puede responder sin leer la tabla (Index Only Scan). Además cubre la
-- FK fk_rt_vino.
-- ---------------------------------------------------------------------
CREATE INDEX idx_renglon_transferencia_vino
    ON renglon_transferencia (cod_vino)
    INCLUDE (nro, cantidad);

-- ---------------------------------------------------------------------
-- 5. Índice simple. Consulta: S4, del lado de la cabecera.
-- La ventana de 15 días conserva 186 de 2.500 transferencias.
-- ---------------------------------------------------------------------
CREATE INDEX idx_transferencia_fecha
    ON transferencia (fecha_confeccion);

COMMIT;
