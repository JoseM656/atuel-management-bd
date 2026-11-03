-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- docs/entregables/etapa 4/consultas_medicion.sql
-- Etapa 4: consultas medidas antes (#31) y después (#33) de 008_indices.sql
--
-- Se ejecuta el mismo archivo en ambas mediciones, para que lo único que
-- cambie entre una y otra sean los índices. El texto de S1, S3, S4, S8 y S10
-- debe coincidir con el de consultas/select.sql (#37).
--
-- Requisito: base cargada con seed.py y --fecha-ref igual a la fecha de la
-- medición, porque S3, S4 y S8 calculan su ventana con CURRENT_DATE.
-- =====================================================================

-- Parámetros de las consignas (se cambian acá)
\set sala_s3 12
\set vino_s4 1

\pset pager off
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas en
-- toda la red de salas.
-- Por qué se mide: agrega la tabla más grande (500.000 renglones) sin filtro.
-- ---------------------------------------------------------------------
\echo '=== S1 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.cod_vino, v.nombre, SUM(r.cantidad) AS botellas
FROM renglon_comprobante r
JOIN vino v ON v.cod_vino = r.cod_vino
GROUP BY v.cod_vino, v.nombre
ORDER BY botellas DESC, v.cod_vino
LIMIT 10;

-- ---------------------------------------------------------------------
-- S3. Cantidad de clientes de cada tipo que compraron en una sala
-- determinada en la última semana.
-- Por qué se mide: filtra comprobante (150.000 filas) por sala y fecha, y
-- devuelve muy pocas filas.
-- ---------------------------------------------------------------------
\echo '=== S3 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT cl.tipo, COUNT(DISTINCT c.id_cliente) AS clientes
FROM comprobante c
JOIN cliente cl ON cl.id_cliente = c.id_cliente
WHERE c.id_sala = :sala_s3
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY cl.tipo;

-- ---------------------------------------------------------------------
-- S4. Top 5 de las salas que solicitaron mayor cantidad de un vino
-- determinado mediante transferencias en los últimos 15 días.
-- Por qué se mide: la PK (nro, cod_vino) no sirve para buscar por cod_vino,
-- porque esa no es su primera columna.
-- ---------------------------------------------------------------------
\echo '=== S4 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.id_sala, SUM(r.cantidad) AS botellas_solicitadas
FROM renglon_transferencia r
JOIN transferencia t ON t.nro = r.nro
WHERE r.cod_vino = :vino_s4
  AND t.fecha_confeccion >= CURRENT_DATE - 15
GROUP BY t.id_sala
ORDER BY botellas_solicitadas DESC, t.id_sala
LIMIT 5;

-- ---------------------------------------------------------------------
-- S8. Monto total de ventas por sala en el último trimestre, en orden
-- descendente.
-- Por qué se mide: filtra comprobante solo por fecha y necesita además
-- id_sala y total.
-- ---------------------------------------------------------------------
\echo '=== S8 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, SUM(c.total) AS monto_total
FROM comprobante c
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY c.id_sala
ORDER BY monto_total DESC;

-- ---------------------------------------------------------------------
-- S10. Rendimiento en kg por hectárea de cada parcela y campaña, e
-- identificar las parcelas que rinden menos que el promedio de su finca.
-- Decisión: el promedio se compara dentro de la misma campaña, para no
-- mezclar años de cosecha distintos.
-- Por qué se mide: la subconsulta correlacionada se evalúa una vez por fila.
-- ---------------------------------------------------------------------
\echo '=== S10 ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH rendimiento AS (
    SELECT l.id_finca,
           l.nro_parcela,
           EXTRACT(YEAR FROM l.fecha_cosecha)::INTEGER AS campana,
           l.kg / p.superficie_ha AS kg_por_ha
    FROM lote_uva l
    JOIN parcela p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela
)
SELECT r.id_finca,
       r.nro_parcela,
       r.campana,
       ROUND(r.kg_por_ha, 2) AS kg_por_ha,
       r.kg_por_ha < (SELECT AVG(r2.kg_por_ha)
                      FROM rendimiento r2
                      WHERE r2.id_finca = r.id_finca
                        AND r2.campana = r.campana) AS rinde_menos_que_finca
FROM rendimiento r
ORDER BY r.id_finca, r.campana, r.nro_parcela;
