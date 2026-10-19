-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/006_vistas.sql
-- Etapa 2: vistas de la base de datos (PostgreSQL 14+)
--
-- Contenido: 3 vistas principales + 1 vista auxiliar para la jerarquía
-- de clientes y reportes de la API/tablero:
--   1. v_stock_total_vino: stock en depósito central + suma de salas por vino.
--   2. v_ventas_mensuales_sala: vista materializada de ventas mensuales por sala.
--   3. v_documentos_pendientes: ingresos y transferencias no procesados (S5).
--   4. v_clientes: unificación de la jerarquía supertipo+subtipos.
--
-- Se aplica después de 001..005, sobre la misma base.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. v_stock_total_vino
-- Propósito: consolidar el stock del depósito central y la suma de stock
--   en todas las salas de venta por cada vino. Utilizada por el tablero,
--   S6 (vinos sin stock en sala pero con stock en depósito) y S9 (ficha de vino).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stock_total_vino AS
SELECT
    v.cod_vino,
    v.nombre,
    v.tipo,
    v.anada,
    v.volumen_ml,
    v.graduacion,
    v.precio,
    v.cuit_bodega,
    b.razon_social AS bodega,
    COALESCE(sd.cantidad, 0)::INTEGER AS stock_deposito,
    COALESCE(SUM(ss.cantidad), 0)::INTEGER AS stock_salas,
    (COALESCE(sd.cantidad, 0) + COALESCE(SUM(ss.cantidad), 0))::INTEGER AS stock_total
FROM vino v
JOIN bodega b ON v.cuit_bodega = b.cuit
LEFT JOIN stock_deposito sd ON v.cod_vino = sd.cod_vino
LEFT JOIN stock_sala ss ON v.cod_vino = ss.cod_vino
GROUP BY
    v.cod_vino,
    v.nombre,
    v.tipo,
    v.anada,
    v.volumen_ml,
    v.graduacion,
    v.precio,
    v.cuit_bodega,
    b.razon_social,
    sd.cantidad;

-- ---------------------------------------------------------------------
-- 2. v_ventas_mensuales_sala (Vista Materializada)
-- Propósito: resumir las ventas acumuladas por sala, año y mes.
--   Al ser una vista materializada, acelera tableros de control y los
--   reportes S8 y S11 sin recalcular sobre millones de comprobantes.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW v_ventas_mensuales_sala AS
SELECT
    s.id_sala,
    (s.calle || ' ' || s.numero) AS sala_direccion,
    l.id_localidad,
    l.nombre AS localidad,
    EXTRACT(YEAR FROM c.fecha)::INTEGER AS anio,
    EXTRACT(MONTH FROM c.fecha)::INTEGER AS mes,
    COUNT(DISTINCT c.nro)::INTEGER AS cant_comprobantes,
    COALESCE(SUM(rc_agg.botellas), 0)::INTEGER AS botellas_vendidas,
    COALESCE(SUM(c.total), 0)::NUMERIC(12,2) AS monto_total
FROM sala_venta s
JOIN localidad l ON s.id_localidad = l.id_localidad
JOIN comprobante c ON c.id_sala = s.id_sala
LEFT JOIN (
    SELECT nro, SUM(cantidad) AS botellas
    FROM renglon_comprobante
    GROUP BY nro
) rc_agg ON rc_agg.nro = c.nro
GROUP BY
    s.id_sala,
    s.calle,
    s.numero,
    l.id_localidad,
    l.nombre,
    EXTRACT(YEAR FROM c.fecha),
    EXTRACT(MONTH FROM c.fecha);

-- Índice único sobre la vista materializada para permitir REFRESH CONCURRENTLY
CREATE UNIQUE INDEX idx_v_ventas_mensuales_sala
    ON v_ventas_mensuales_sala (id_sala, anio, mes);

-- ---------------------------------------------------------------------
-- 3. v_documentos_pendientes
-- Propósito: unificar los ingresos y transferencias que no han sido
--   procesados (estado = 'en_confeccion' o 'terminado'). Utilizada por
--   el módulo logístico y la consulta S5.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_documentos_pendientes AS
SELECT
    'ingreso'::VARCHAR(20) AS tipo_documento,
    i.cod_ingreso AS id_documento,
    i.fecha AS fecha,
    i.estado AS estado,
    i.cuit_bodega AS origen_destino_id,
    b.razon_social AS origen_destino_nombre,
    i.cod_transportista AS cod_transportista,
    t.razon_social AS transportista,
    NULL::INTEGER AS id_sala,
    COUNT(DISTINCT ri.cod_vino)::INTEGER AS cant_vinos_distintos,
    COALESCE(SUM(ri.cantidad), 0)::INTEGER AS total_botellas
FROM ingreso i
JOIN bodega b ON i.cuit_bodega = b.cuit
JOIN transportista t ON i.cod_transportista = t.cod_transportista
LEFT JOIN renglon_ingreso ri ON i.cod_ingreso = ri.cod_ingreso
WHERE i.estado <> 'procesado'
GROUP BY i.cod_ingreso, i.fecha, i.estado, i.cuit_bodega, b.razon_social, i.cod_transportista, t.razon_social

UNION ALL

SELECT
    'transferencia'::VARCHAR(20) AS tipo_documento,
    t.nro AS id_documento,
    t.fecha_confeccion AS fecha,
    t.estado AS estado,
    t.id_sala::VARCHAR AS origen_destino_id,
    ('Sala ' || s.id_sala || ' (' || s.calle || ' ' || s.numero || ')') AS origen_destino_nombre,
    NULL::INTEGER AS cod_transportista,
    NULL::VARCHAR AS transportista,
    t.id_sala AS id_sala,
    COUNT(DISTINCT rt.cod_vino)::INTEGER AS cant_vinos_distintos,
    COALESCE(SUM(rt.cantidad), 0)::INTEGER AS total_botellas
FROM transferencia t
JOIN sala_venta s ON t.id_sala = s.id_sala
LEFT JOIN renglon_transferencia rt ON t.nro = rt.nro
WHERE t.estado <> 'procesado'
GROUP BY t.nro, t.fecha_confeccion, t.estado, t.id_sala, s.calle, s.numero;

-- ---------------------------------------------------------------------
-- 4. v_clientes
-- Propósito: resolver los joins entre el supertipo cliente y sus subtipos
--   (socio, distribuidor, exportador), consolidando atributos propios y
--   el conteo de permisos de exportación. Utilizada por la API y consultas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_clientes AS
SELECT
    c.id_cliente,
    c.nombre_razon_social,
    c.tipo_doc,
    c.nro_doc,
    c.direccion,
    c.id_localidad,
    l.nombre AS localidad,
    l.provincia AS provincia,
    c.fecha_alta,
    c.tipo,
    c.descuento,
    d.zona_cobertura,
    d.nro_habilitacion,
    e.pais_destino,
    COALESCE(p.cant_permisos, 0)::INTEGER AS cant_permisos_exportacion
FROM cliente c
JOIN localidad l ON c.id_localidad = l.id_localidad
LEFT JOIN socio s ON c.id_cliente = s.id_cliente
LEFT JOIN distribuidor d ON c.id_cliente = d.id_cliente
LEFT JOIN exportador e ON c.id_cliente = e.id_cliente
LEFT JOIN (
    SELECT id_cliente, COUNT(*) AS cant_permisos
    FROM permiso_exportacion
    GROUP BY id_cliente
) p ON c.id_cliente = p.id_cliente;

COMMIT;
