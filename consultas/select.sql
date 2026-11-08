-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- consultas/select.sql — Etapa 5 · Consultas (S1–S12) (#37)
--
-- Contenido: las consultas SELECT de la sección 8.4 (S1–S8) y las
-- avanzadas de la sección 8.5 (S9–S12). Cada consigna lleva: código,
-- enunciado, estrategia y la consulta. S9–S12 incluyen
-- EXPLAIN (ANALYZE, BUFFERS), como pide el criterio de aceptación.
--
-- Coordinación con la Etapa 4 (índices): el texto de S1, S3, S4, S5, S8
-- y S10 coincide exactamente con el de
-- docs/entregables/etapa 4/consultas_medicion.sql, para que el informe
-- de índices mida la misma consulta que se entrega acá. S3 y S4 usan los
-- mismos parámetros (sala 12 y vino 1).
--
-- Requisito: base migrada (001–008) y cargada con db/seed/seed.py
-- (semilla 42). Las ventanas «última semana», «último mes» y «último
-- trimestre» se calculan desde CURRENT_DATE, no con fechas fijas.
--
-- Rol: solo lectura; puede ejecutarse como postgres, propietario o
-- reportes_ro. No modifica datos.
-- =====================================================================

\pset pager off
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Parámetros de las consignas (se cambian acá). No están hardcodeados
-- en el cuerpo de las consultas, igual que en consultas_medicion.sql.
--   sala_s3   : sala determinada de S3 (id de sala_venta).
--   vino_s4   : vino determinado de S4 (cod_vino).
--   sala_s6   : sala determinada de S6 (id de sala_venta).
--   vino_s9   : vino de la ficha de S9 (cod_vino).
--   cuit_bodega_s12: bodega determinada de S12 (CUIT, PK de bodega).
-- ---------------------------------------------------------------------
\set sala_s3 12
\set vino_s4 1
\set sala_s6 12
\set vino_s9 1
-- Bodega Atuel del Sur S.A. (CUIT 30700000019)
\set cuit_bodega_s12 '30700000019'

-- =====================================================================
-- S1 · Ranking de los 10 vinos con mayor cantidad de botellas vendidas
--      en toda la red de salas.
--
-- Estrategia: agregación simple sobre renglon_comprobante (la tabla más
-- grande, ~500.000 filas) agrupada por vino, ordenada por la suma de
-- cantidades y limitada a 10. No hay filtro que un índice pueda
-- aprovechar: se lee toda la tabla (ver informe de la Etapa 4).
--
-- Texto idéntico al de consultas_medicion.sql (#37).
-- =====================================================================
\echo '=== S1 ==='
SELECT v.cod_vino, v.nombre, SUM(r.cantidad) AS botellas
FROM renglon_comprobante r
JOIN vino v ON v.cod_vino = r.cod_vino
GROUP BY v.cod_vino, v.nombre
ORDER BY botellas DESC, v.cod_vino
LIMIT 10;

-- =====================================================================
-- S2 · Listar códigos y nombres de los vinos que se vendieron en TODAS
--      las salas (división relacional).
--
-- Estrategia: división relacional con doble NOT EXISTS. Un vino cumple
-- la consigna si NO existe ninguna sala en la que NO haya sido vendido.
-- La sala exterior recorre sala_venta y la interior comprueba, por sala,
-- que haya un renglón de comprobante con ese vino.
-- =====================================================================
\echo '=== S2 ==='
SELECT v.cod_vino, v.nombre
FROM vino v
WHERE NOT EXISTS (
    SELECT 1 FROM sala_venta s
    WHERE NOT EXISTS (
        SELECT 1
        FROM comprobante c
        JOIN renglon_comprobante r ON r.nro = c.nro
        WHERE c.id_sala = s.id_sala
          AND r.cod_vino = v.cod_vino
    )
)
ORDER BY v.cod_vino;

-- =====================================================================
-- S3 · Cantidad de clientes de cada tipo que compraron en una sala
--      determinada en la última semana.
--
-- Estrategia: filtro de comprobante por sala y por fecha (CURRENT_DATE)
-- y agregación por tipo de cliente, contando clientes distintos.
--
-- Parámetro: sala :sala_s3. Texto idéntico al de consultas_medicion.sql.
-- =====================================================================
\echo '=== S3 ==='
SELECT cl.tipo, COUNT(DISTINCT c.id_cliente) AS clientes
FROM comprobante c
JOIN cliente cl ON cl.id_cliente = c.id_cliente
WHERE c.id_sala = :sala_s3
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY cl.tipo;

-- =====================================================================
-- S4 · Top 5 de las salas que solicitaron mayor cantidad de un vino
--      determinado mediante transferencias en los últimos 15 días.
--
-- Estrategia: join renglon_transferencia → transferencia, filtro por
-- vino y por fecha de confección, suma de cantidades por sala y límite 5.
-- La PK (nro, cod_vino) no sirve para buscar por cod_vino (no es su
-- primera columna), por eso la Etapa 4 crea un índice sobre cod_vino.
--
-- Parámetro: vino :vino_s4. Texto idéntico al de consultas_medicion.sql.
-- =====================================================================
\echo '=== S4 ==='
SELECT t.id_sala, SUM(r.cantidad) AS botellas_solicitadas
FROM renglon_transferencia r
JOIN transferencia t ON t.nro = r.nro
WHERE r.cod_vino = :vino_s4
  AND t.fecha_confeccion >= CURRENT_DATE - 15
GROUP BY t.id_sala
ORDER BY botellas_solicitadas DESC, t.id_sala
LIMIT 5;

-- =====================================================================
-- S5 · Listado de las salas con menor cantidad de transferencias
--      pendientes (no procesadas).
--
-- Estrategia: LEFT JOIN de sala_venta contra transferencia filtrando el
-- estado en la condición del join, de modo que cada sala se conserve
-- aunque no tenga pendientes (COUNT da 0). Se ordena de menor a mayor.
--
-- Texto idéntico al de consultas_medicion.sql.
-- =====================================================================
\echo '=== S5 ==='
SELECT s.id_sala, COUNT(t.nro) AS pendientes
FROM sala_venta s
LEFT JOIN transferencia t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
GROUP BY s.id_sala
ORDER BY pendientes, s.id_sala;

-- =====================================================================
-- S6 · Para una sala determinada, los vinos sin stock en la sala pero
--      con stock en el depósito central.
--
-- Estrategia: anti-join con NOT EXISTS. Se toman los vinos con stock
-- positivo en stock_deposito y se descartan los que tienen una fila de
-- stock_sala con cantidad > 0 en la sala indicada. El NOT EXISTS cubre
-- tanto «no hay fila en stock_sala» como «hay fila con cantidad 0».
--
-- Parámetro: sala :sala_s6 (no hardcodeado; se cambia en el encabezado).
-- =====================================================================
\echo '=== S6 ==='
SELECT v.cod_vino, v.nombre, sd.cantidad AS stock_deposito
FROM stock_deposito sd
JOIN vino v ON v.cod_vino = sd.cod_vino
WHERE sd.cantidad > 0
  AND NOT EXISTS (
      SELECT 1
      FROM stock_sala ss
      WHERE ss.id_sala = :sala_s6
        AND ss.cod_vino = sd.cod_vino
        AND ss.cantidad > 0
  )
ORDER BY v.cod_vino;

-- =====================================================================
-- S7 · ¿Cuál es la empresa de transporte con mayor actividad en el
--      último mes?
--
-- Estrategia: se mide la actividad como la cantidad de ingresos
-- trasladados por cada transportista en el último mes (los transportistas
-- solo intervienen en ingresos; las transferencias no llevan
-- transportista). Se agrupa por transportista, se ordena por cantidad
-- descendente y se toma el primero. En caso de empate gana el de menor
-- código.
-- =====================================================================
\echo '=== S7 ==='
SELECT t.cod_transportista, t.razon_social, COUNT(i.cod_ingreso) AS ingresos_trasladados
FROM transportista t
JOIN ingreso i ON i.cod_transportista = t.cod_transportista
WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
GROUP BY t.cod_transportista, t.razon_social
ORDER BY ingresos_trasladados DESC, t.cod_transportista
LIMIT 1;

-- =====================================================================
-- S8 · Monto total de ventas por sala en el último trimestre, en orden
--      descendente.
--
-- Estrategia: filtro de comprobante solo por fecha y suma de totales por
-- sala. El total es una columna materializada de comprobante (RN-08).
--
-- Texto idéntico al de consultas_medicion.sql.
-- =====================================================================
\echo '=== S8 ==='
SELECT c.id_sala, SUM(c.total) AS monto_total
FROM comprobante c
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY c.id_sala
ORDER BY monto_total DESC;

-- =====================================================================
-- S9 (avanzada) · Ficha de un vino: cepas con sus porcentajes, bodega
--      elaboradora, maridajes y stock total (depósito más salas).
--
-- Herramientas: joins, agregación y vista.
--   · El stock total sale de la vista v_stock_total_vino (006_vistas.sql),
--     que ya suma depósito + salas por vino.
--   · Cepas y maridajes se agregan con string_agg sobre subconsultas,
--     evitando el producto cartesiano entre composición y maridaje que
--     surgiría al unir ambas tablas N:M a la vez.
--
-- Parámetro: vino :vino_s9.
-- =====================================================================
\echo '=== S9 · resultado ==='
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.anada,
       v.volumen_ml,
       v.graduacion,
       v.precio,
       b.razon_social AS bodega,
       st.stock_total,
       (SELECT string_agg(c.nombre || ' ' || co.porcentaje::text || '%', ', '
                          ORDER BY co.porcentaje DESC, c.nombre)
        FROM composicion co
        JOIN cepa c ON c.id_cepa = co.id_cepa
        WHERE co.cod_vino = v.cod_vino) AS cepas,
       (SELECT string_agg(m.nombre || ' (' || m.temperatura_servicio::text || '°C)', ', '
                          ORDER BY m.nombre)
        FROM vino_maridaje vm
        JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
        WHERE vm.cod_vino = v.cod_vino) AS maridajes
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino
WHERE v.cod_vino = :vino_s9;

\echo '=== S9 · plan ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.anada,
       v.volumen_ml,
       v.graduacion,
       v.precio,
       b.razon_social AS bodega,
       st.stock_total,
       (SELECT string_agg(c.nombre || ' ' || co.porcentaje::text || '%', ', '
                          ORDER BY co.porcentaje DESC, c.nombre)
        FROM composicion co
        JOIN cepa c ON c.id_cepa = co.id_cepa
        WHERE co.cod_vino = v.cod_vino) AS cepas,
       (SELECT string_agg(m.nombre || ' (' || m.temperatura_servicio::text || '°C)', ', '
                          ORDER BY m.nombre)
        FROM vino_maridaje vm
        JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
        WHERE vm.cod_vino = v.cod_vino) AS maridajes
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino
WHERE v.cod_vino = :vino_s9;

-- =====================================================================
-- S10 (avanzada) · Rendimiento en kg por hectárea de cada parcela y
--      campaña, e identificar las parcelas que rinden menos que el
--      promedio de su finca.
--
-- Herramientas: CTE y subconsulta correlacionada.
--
-- Decisión: el promedio se compara dentro de la misma campaña, para no
-- mezclar años de cosecha distintos. La campaña se deriva del año de
-- fecha_cosecha (no hay columna campaña).
--
-- Nota de rendimiento: la subconsulta correlacionada recorre el CTE una
-- vez por fila (~530 ms) y no se resuelve con índices (ver informe de la
-- Etapa 4). Cumple con la consigna (CTE + subconsulta correlacionada).
--
-- Texto idéntico al de consultas_medicion.sql.
-- =====================================================================
\echo '=== S10 · resultado ==='
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

\echo '=== S10 · plan ==='
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

-- =====================================================================
-- S11 (avanzada) · Ranking de vinos dentro de cada sala por botellas
--      vendidas, y ventas acumuladas mensuales por sala.
--
-- Herramientas: RANK() OVER (PARTITION BY …) y suma acumulada con ventana.
--
-- Se resuelve en una sola sentencia con dos bloques (UNION ALL), porque
-- las dos medidas viven en granularidades distintas:
--   1) 'ranking_vinos': por (sala, vino), RANK dentro de cada sala
--      ordenado por botellas vendidas.
--   2) 'acumulado_mensual': por (sala, mes), suma corrida del monto con
--      SUM(...) OVER (PARTITION BY id_sala ORDER BY anio, mes).
-- Las columnas que no aplican a cada bloque van en NULL.
-- =====================================================================
\echo '=== S11 · resultado ==='
SELECT 'ranking_vinos'::text AS reporte,
       c.id_sala,
       v.cod_vino,
       v.nombre,
       SUM(r.cantidad) AS botellas,
       RANK() OVER (PARTITION BY c.id_sala ORDER BY SUM(r.cantidad) DESC) AS ranking,
       NULL::INTEGER AS anio,
       NULL::INTEGER AS mes,
       NULL::NUMERIC(12,2) AS monto_mensual,
       NULL::NUMERIC(12,2) AS monto_acumulado
FROM comprobante c
JOIN renglon_comprobante r ON r.nro = c.nro
JOIN vino v ON v.cod_vino = r.cod_vino
GROUP BY c.id_sala, v.cod_vino, v.nombre

UNION ALL

SELECT 'acumulado_mensual'::text AS reporte,
       id_sala,
       NULL::INTEGER AS cod_vino,
       NULL::VARCHAR AS nombre,
       NULL::BIGINT AS botellas,
       NULL::BIGINT AS ranking,
       anio,
       mes,
       monto_mensual,
       SUM(monto_mensual) OVER (PARTITION BY id_sala ORDER BY anio, mes
                                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS monto_acumulado
FROM (
    SELECT id_sala,
           EXTRACT(YEAR FROM fecha)::INTEGER AS anio,
           EXTRACT(MONTH FROM fecha)::INTEGER AS mes,
           SUM(total) AS monto_mensual
    FROM comprobante
    GROUP BY id_sala, EXTRACT(YEAR FROM fecha), EXTRACT(MONTH FROM fecha)
) vm

ORDER BY reporte, id_sala, ranking NULLS LAST, anio NULLS LAST, mes NULLS LAST;

\echo '=== S11 · plan ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT 'ranking_vinos'::text AS reporte,
       c.id_sala,
       v.cod_vino,
       v.nombre,
       SUM(r.cantidad) AS botellas,
       RANK() OVER (PARTITION BY c.id_sala ORDER BY SUM(r.cantidad) DESC) AS ranking,
       NULL::INTEGER AS anio,
       NULL::INTEGER AS mes,
       NULL::NUMERIC(12,2) AS monto_mensual,
       NULL::NUMERIC(12,2) AS monto_acumulado
FROM comprobante c
JOIN renglon_comprobante r ON r.nro = c.nro
JOIN vino v ON v.cod_vino = r.cod_vino
GROUP BY c.id_sala, v.cod_vino, v.nombre

UNION ALL

SELECT 'acumulado_mensual'::text AS reporte,
       id_sala,
       NULL::INTEGER AS cod_vino,
       NULL::VARCHAR AS nombre,
       NULL::BIGINT AS botellas,
       NULL::BIGINT AS ranking,
       anio,
       mes,
       monto_mensual,
       SUM(monto_mensual) OVER (PARTITION BY id_sala ORDER BY anio, mes
                                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS monto_acumulado
FROM (
    SELECT id_sala,
           EXTRACT(YEAR FROM fecha)::INTEGER AS anio,
           EXTRACT(MONTH FROM fecha)::INTEGER AS mes,
           SUM(total) AS monto_mensual
    FROM comprobante
    GROUP BY id_sala, EXTRACT(YEAR FROM fecha), EXTRACT(MONTH FROM fecha)
) vm

ORDER BY reporte, id_sala, ranking NULLS LAST, anio NULLS LAST, mes NULLS LAST;

-- =====================================================================
-- S12 (avanzada) · Dos divisiones/anti-joins con NOT EXISTS:
--   a) Clientes que compraron TODOS los vinos de una bodega determinada.
--   b) Clientes que NUNCA compraron ningún vino tinto.
--
-- Herramientas: NOT EXISTS (división) y anti-join.
--
-- S12a: división relacional. Un cliente cumple si NO existe ningún vino
-- de la bodega elegida para el que NO exista un renglón suyo. Con una
-- bodega de 20 vinos, es esperable que devuelva pocos (o ningún) cliente:
-- es la semántica correcta de la división.
--
-- S12b: anti-join. Un cliente cumple si NO existe ningún comprobante suyo
-- que contenga un vino de tipo tinto.
--
-- Parámetro: bodega :'cuit_bodega_s12' (CUIT, en el encabezado).
-- S12a devuelve 0 filas si la bodega no existe o no tiene vinos.
-- =====================================================================
\echo '=== S12a · resultado ==='
SELECT c.id_cliente, c.nombre_razon_social
FROM cliente c
WHERE EXISTS (                       -- guarda: la bodega existe y tiene vinos
    SELECT 1 FROM vino v WHERE v.cuit_bodega = :'cuit_bodega_s12'
)
AND NOT EXISTS (
    SELECT 1
    FROM vino v
    WHERE v.cuit_bodega = :'cuit_bodega_s12'
      AND NOT EXISTS (
          SELECT 1
          FROM comprobante co
          JOIN renglon_comprobante rc ON rc.nro = co.nro
          WHERE co.id_cliente = c.id_cliente
            AND rc.cod_vino = v.cod_vino
      )
)
ORDER BY c.id_cliente;

\echo '=== S12a · plan ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_cliente, c.nombre_razon_social
FROM cliente c
WHERE EXISTS (                       -- guarda: la bodega existe y tiene vinos
    SELECT 1 FROM vino v WHERE v.cuit_bodega = :'cuit_bodega_s12'
)
AND NOT EXISTS (
    SELECT 1
    FROM vino v
    WHERE v.cuit_bodega = :'cuit_bodega_s12'
      AND NOT EXISTS (
          SELECT 1
          FROM comprobante co
          JOIN renglon_comprobante rc ON rc.nro = co.nro
          WHERE co.id_cliente = c.id_cliente
            AND rc.cod_vino = v.cod_vino
      )
)
ORDER BY c.id_cliente;

\echo '=== S12b · resultado ==='
SELECT c.id_cliente, c.nombre_razon_social
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1
    FROM comprobante co
    JOIN renglon_comprobante rc ON rc.nro = co.nro
    JOIN vino v ON v.cod_vino = rc.cod_vino
    WHERE co.id_cliente = c.id_cliente
      AND v.tipo = 'tinto'
)
ORDER BY c.id_cliente;

\echo '=== S12b · plan ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_cliente, c.nombre_razon_social
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1
    FROM comprobante co
    JOIN renglon_comprobante rc ON rc.nro = co.nro
    JOIN vino v ON v.cod_vino = rc.cod_vino
    WHERE co.id_cliente = c.id_cliente
      AND v.tipo = 'tinto'
)
ORDER BY c.id_cliente;