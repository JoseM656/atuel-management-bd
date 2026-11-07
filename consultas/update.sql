-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- consultas/update.sql
-- Sección 8.1 del enunciado: modificación de datos (U1 a U6)
--
-- Requiere: base migrada y cargada con db/seed/seed.py.
-- Ejecución: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f consultas/update.sql
--
-- Cada consigna corre en su propia transacción: BEGIN, control previo,
-- sentencia, control posterior y ROLLBACK. Por eso el archivo no deja
-- cambios en la base y se puede volver a ejecutar.
--
-- Los resultados anotados salen de una carga con semilla 42 y
-- --fecha-ref 2026-11-05.
-- =====================================================================


-- ---------------------------------------------------------------------
-- U1. Recalcular el total de todos los comprobantes aplicando el descuento
-- que corresponde al tipo de cliente.
--
-- Estrategia: la sentencia solo actualiza porcentaje_descuento con
-- fn_descuento_cliente (RN-06, RI-06), y el total lo calcula la base.
-- No lleva WHERE porque trg_comprobante_importes recalcula el total de cada
-- fila actualizada, aunque el porcentaje no cambie. Filtrar por porcentaje
-- distinto dejaría sin corregir un total que esté mal por otra causa.
-- La columna total no se escribe en la sentencia, porque RN-08 rechaza un
-- total distinto del que surge de los renglones.
--
-- Triggers que se disparan:
--   - trg_comprobante_importes: recalcula subtotal y total en cada fila.
--   - trg_comprobante_propaga_descuento: si el porcentaje cambió, actualiza
--     el descuento y el subtotal de los renglones de ese comprobante.
--   - trg_renglon_comprobante_bud: valida esos renglones.
--   - trg_cliente_subtipo: lo dispara la preparación, porque
--     trg_permiso_descuento actualiza el descuento del cliente. Es diferido;
--     SET CONSTRAINTS ALL IMMEDIATE lo evalúa antes del ROLLBACK.
--
-- Preparación de la prueba: en el seed todos los comprobantes ya tienen el
-- descuento correcto, así que U1 no cambiaría ningún importe. Para ver un
-- cambio real se le agrega un cuarto permiso a un exportador que tiene tres.
-- trg_permiso_descuento le sube el descuento al 35 % (RI-06), pero sus
-- comprobantes anteriores siguen con el 30 %.
--
-- Efecto a tener en cuenta: porcentaje_descuento es la copia histórica del
-- descuento vigente al momento de la venta. U1 la reemplaza por el descuento
-- actual, así que también cambia ventas ya realizadas.
--
-- Control: totales_incorrectos cuenta los comprobantes cuyo total no es la
-- suma de sus renglones con el descuento actual del cliente, calculado
-- como lo hace trg_comprobante_importes.
--
-- Resultado medido:
--   - Filas afectadas: 150.000. En 83 comprobantes cambia el importe.
--   - Control previo: 83 totales incorrectos; suma 10.707.050.390,00.
--   - Control posterior: 0 totales incorrectos; suma 10.706.704.095,00.
--   - Sin la preparación, el control previo da 0: el seed ya está al día.
--   - Tarda entre 4 y 14 s según la caché, porque por cada comprobante se
--     ejecutan la función y el trigger que suma sus renglones.
-- ---------------------------------------------------------------------
BEGIN;

-- Preparación: cuarto permiso para el primer exportador con tres permisos
-- y al menos un comprobante.
INSERT INTO permiso_exportacion (codigo, id_cliente, fecha_emision, fecha_vencimiento)
SELECT 'PRUEBA-U1', p.id_cliente, CURRENT_DATE, CURRENT_DATE + 365
FROM permiso_exportacion p
WHERE EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = p.id_cliente)
GROUP BY p.id_cliente
HAVING count(*) = 3
ORDER BY p.id_cliente
LIMIT 1;

-- Control previo
SELECT count(*) AS comprobantes,
       count(*) FILTER (WHERE c.total <> ROUND(COALESCE(r.suma, 0)
                        * (1 - fn_descuento_cliente(c.id_cliente) / 100.0), 2)) AS totales_incorrectos,
       sum(c.total) AS suma_totales
FROM comprobante c
LEFT JOIN (SELECT nro, sum(cantidad * precio_unitario) AS suma
           FROM renglon_comprobante
           GROUP BY nro) r USING (nro);

UPDATE comprobante
SET porcentaje_descuento = fn_descuento_cliente(id_cliente);

SET CONSTRAINTS ALL IMMEDIATE;

-- Control posterior
SELECT count(*) AS comprobantes,
       count(*) FILTER (WHERE c.total <> ROUND(COALESCE(r.suma, 0)
                        * (1 - fn_descuento_cliente(c.id_cliente) / 100.0), 2)) AS totales_incorrectos,
       sum(c.total) AS suma_totales
FROM comprobante c
LEFT JOIN (SELECT nro, sum(cantidad * precio_unitario) AS suma
           FROM renglon_comprobante
           GROUP BY nro) r USING (nro);

ROLLBACK;


-- ---------------------------------------------------------------------
-- U2. Aumentar un 20 % el salario de los empleados con más de 5 años de
-- antigüedad.
--
-- Estrategia: un UPDATE con la condición sobre fecha_ingreso. «Más de 5
-- años» se toma literal: ingresó antes de la fecha de hoy menos 5 años.
-- Quien cumple justo 5 años hoy no entra, porque todavía no los superó.
--
-- No se usa fn_antiguedad_anios(fecha_ingreso) > 5: esa función devuelve
-- años completos, así que un empleado con 5 años y 8 meses daría 5 y
-- quedaría afuera. Sobre el seed los dos criterios eligen los mismos 44
-- empleados, porque ninguno tiene entre 4 y 6 años.
--
-- ROUND deja el salario en 2 decimales, el formato de NUMERIC(12,2).
--
-- Depende de CURRENT_DATE: con el paso de los días puede entrar algún
-- empleado más.
--
-- Triggers y constraints:
--   - ck_empleado_salario: el salario sigue siendo mayor que 0.
--   - trg_encargado_empleado (RI-01): es diferido, así que normalmente se
--     evaluaría en el COMMIT. SET CONSTRAINTS ALL IMMEDIATE lo evalúa antes
--     del ROLLBACK, para comprobar que el cambio lo cumple.
--
-- Resultado medido (CURRENT_DATE 2026-11-07):
--   - Filas afectadas: 44 de 120.
--   - Control previo: suma de sus salarios 40.100.000,00; resto 75.160.000,00.
--   - Control posterior: suma de sus salarios 48.120.000,00 (+20 %); resto
--     sin cambios.
-- ---------------------------------------------------------------------
BEGIN;

-- Control previo
SELECT count(*) FILTER (WHERE fecha_ingreso < CURRENT_DATE - INTERVAL '5 years') AS con_mas_de_5_anios,
       sum(salario) FILTER (WHERE fecha_ingreso < CURRENT_DATE - INTERVAL '5 years') AS salarios_con_aumento,
       sum(salario) FILTER (WHERE fecha_ingreso >= CURRENT_DATE - INTERVAL '5 years') AS salarios_resto
FROM empleado;

UPDATE empleado
SET salario = ROUND(salario * 1.20, 2)
WHERE fecha_ingreso < CURRENT_DATE - INTERVAL '5 years';

SET CONSTRAINTS ALL IMMEDIATE;

-- Control posterior
SELECT count(*) FILTER (WHERE fecha_ingreso < CURRENT_DATE - INTERVAL '5 years') AS con_mas_de_5_anios,
       sum(salario) FILTER (WHERE fecha_ingreso < CURRENT_DATE - INTERVAL '5 years') AS salarios_con_aumento,
       sum(salario) FILTER (WHERE fecha_ingreso >= CURRENT_DATE - INTERVAL '5 years') AS salarios_resto
FROM empleado;

ROLLBACK;


-- ---------------------------------------------------------------------
-- U3. Incrementar un 13 % el precio de los vinos elaborados por una bodega
-- determinada.
--
-- Parámetro: la razón social de la bodega, en la línea \set de abajo.
-- Se usa la variable :'bodega' de psql para escribir el valor una sola vez.
--
-- Estrategia: un UPDATE de vino con una subconsulta que traduce la razón
-- social al CUIT de la bodega. Si la subconsulta no encuentra la bodega,
-- devuelve NULL y no se actualiza ninguna fila. Si encontrara más de una,
-- la sentencia falla en lugar de subir precios de otra bodega.
-- ROUND deja el precio en 2 decimales, el formato de NUMERIC(12,2).
--
-- Triggers y constraints:
--   - trg_vino_auditoria_precio (RN-13): por cada vino cuyo precio cambia
--     inserta una fila en auditoria_precio con el precio anterior, el nuevo,
--     la fecha y hora y el usuario.
--   - ck_vino_precio: el precio sigue siendo mayor que 0.
--   - trg_vino_maridaje_obligatorio: es diferido; SET CONSTRAINTS ALL
--     IMMEDIATE lo evalúa antes del ROLLBACK.
--
-- Las ventas ya realizadas no cambian: renglon_comprobante guarda su propio
-- precio_unitario, copiado del vino al momento de vender (RI-03).
--
-- Control: las filas de auditoría de esta transacción se reconocen porque
-- su fecha_hora es now(), que en PostgreSQL es la hora de inicio de la
-- transacción.
--
-- Resultado medido:
--   - Filas afectadas: 20 vinos de 400.
--   - Precios de la bodega: suma 193.300,00 antes y 218.429,00 después.
--   - Precios de las otras bodegas: 3.520.700,00 antes y después.
--   - Auditoría: de 400 a 420 filas. Las 20 nuevas tienen precio_nuevo
--     igual a precio_anterior × 1,13 redondeado.
-- ---------------------------------------------------------------------
\set bodega 'Bodega Atuel del Sur S.A.'

BEGIN;

-- Control previo
SELECT count(*) FILTER (WHERE b.razon_social = :'bodega') AS vinos_de_la_bodega,
       sum(v.precio) FILTER (WHERE b.razon_social = :'bodega') AS precios_de_la_bodega,
       sum(v.precio) FILTER (WHERE b.razon_social <> :'bodega') AS precios_otras_bodegas,
       (SELECT count(*) FROM auditoria_precio) AS filas_auditoria
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega;

UPDATE vino
SET precio = ROUND(precio * 1.13, 2)
WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega');

SET CONSTRAINTS ALL IMMEDIATE;

-- Control posterior
SELECT count(*) FILTER (WHERE b.razon_social = :'bodega') AS vinos_de_la_bodega,
       sum(v.precio) FILTER (WHERE b.razon_social = :'bodega') AS precios_de_la_bodega,
       sum(v.precio) FILTER (WHERE b.razon_social <> :'bodega') AS precios_otras_bodegas,
       (SELECT count(*) FROM auditoria_precio) AS filas_auditoria
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega;

-- Auditoría generada por esta transacción
SELECT count(*) AS filas_nuevas,
       count(*) FILTER (WHERE precio_nuevo = ROUND(precio_anterior * 1.13, 2)) AS con_13_por_ciento,
       min(usuario) AS usuario
FROM auditoria_precio
WHERE fecha_hora = now();

ROLLBACK;


-- ---------------------------------------------------------------------
-- U4. En las salas cuyo día de cierre es lunes cambiarlo a miércoles y
-- viceversa, en una sola sentencia.
--
-- Estrategia: un UPDATE con CASE. El WHERE limita la sentencia a las salas
-- que cierran lunes o miércoles, y el CASE elige el día opuesto.
--
-- Por qué funciona en una sola sentencia: el CASE de cada fila lee el
-- valor que tenía antes del UPDATE, no el que la sentencia ya escribió en
-- otras filas. Con dos sentencias seguidas (lunes -> miércoles y después
-- miércoles -> lunes), la segunda también tomaría las salas que la primera
-- acababa de pasar a miércoles, y todas terminarían cerrando los lunes.
--
-- Los literales del CASE llevan el tipo dia_semana. Sin ese cast, el CASE
-- da un resultado de tipo text y PostgreSQL no lo asigna a la columna ENUM.
--
-- Triggers: trg_encargado_sala (RI-01) es diferido; SET CONSTRAINTS ALL
-- IMMEDIATE lo evalúa antes del ROLLBACK. El día de cierre no interviene en
-- esa regla, así que no puede fallar por este cambio.
--
-- Control: los IDs de las salas de cada grupo, antes y después.
--
-- Resultado medido:
--   - Filas afectadas: 27 de 36 salas (14 cerraban los lunes y 13 los
--     miércoles).
--   - Las salas de cada grupo pasan completas al otro día. Las otras 9
--     salas no cambian.
-- ---------------------------------------------------------------------
BEGIN;

-- Control previo
SELECT dia_cierre, count(*) AS salas, string_agg(id_sala::text, ',' ORDER BY id_sala) AS ids
FROM sala_venta
GROUP BY dia_cierre
ORDER BY dia_cierre;

UPDATE sala_venta
SET dia_cierre = CASE dia_cierre
                     WHEN 'lunes'::dia_semana THEN 'miercoles'::dia_semana
                     ELSE 'lunes'::dia_semana
                 END
WHERE dia_cierre IN ('lunes', 'miercoles');

SET CONSTRAINTS ALL IMMEDIATE;

-- Control posterior
SELECT dia_cierre, count(*) AS salas, string_agg(id_sala::text, ',' ORDER BY id_sala) AS ids
FROM sala_venta
GROUP BY dia_cierre
ORDER BY dia_cierre;

ROLLBACK;


-- ---------------------------------------------------------------------
-- U5. Aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos
-- de toda la red.
--
-- Criterio:
--   - «La red» son las salas de venta. Entran los vinos que llegaron a
--     alguna sala, es decir, los que tienen fila en stock_sala.
--   - «Menos vendidos» se mide en unidades: la suma de cantidad en
--     renglon_comprobante de todas las salas. Un vino que está en una sala
--     y nunca se vendió cuenta con 0 unidades.
--   - Los vinos que nunca llegaron a una sala no entran, porque no tuvieron
--     oportunidad de venderse. En el seed son 152 de 400: si se contaran,
--     habría 152 empatados en 0 unidades y elegir 10 sería arbitrario.
--   - Si hubiera empate en el décimo puesto, decide el menor cod_vino. En el
--     seed no hay empate: el décimo vendió 1.248 unidades y el undécimo 1.251.
--
-- Estrategia: la CTE ventas suma las unidades por vino. LEFT JOIN mantiene
-- los vinos sin ventas y COALESCE les asigna 0. La CTE menos_vendidos ordena
-- y se queda con 10, y el UPDATE baja el precio de esos vinos.
-- ROUND deja el precio en 2 decimales, el formato de NUMERIC(12,2).
--
-- Triggers y constraints:
--   - trg_vino_auditoria_precio (RN-13): una fila de auditoría por vino.
--   - ck_vino_precio: el precio sigue siendo mayor que 0.
--   - trg_vino_maridaje_obligatorio: es diferido; SET CONSTRAINTS ALL
--     IMMEDIATE lo evalúa antes del ROLLBACK.
--
-- Control previo: los 11 vinos con menos ventas. El undécimo muestra que el
-- corte en 10 no deja afuera un empate. Control posterior: la auditoría de
-- esta transacción, con el precio anterior y el nuevo de cada vino.
--
-- Resultado medido:
--   - Filas afectadas: 10.
--   - Vinos elegidos (unidades): 392 (139), 7 (141), 11 (696), 15 (698),
--     391 (1.108), 389 (1.110), 6 (1.113), 8 (1.115), 384 (1.247) y
--     390 (1.248).
--   - Auditoría: 10 filas nuevas, con precio_nuevo igual a
--     precio_anterior × 0,85 redondeado.
-- ---------------------------------------------------------------------
BEGIN;

-- Control previo
WITH ventas AS (
    SELECT s.cod_vino, COALESCE(sum(r.cantidad), 0) AS unidades
    FROM (SELECT DISTINCT cod_vino FROM stock_sala) s
    LEFT JOIN renglon_comprobante r ON r.cod_vino = s.cod_vino
    GROUP BY s.cod_vino
)
SELECT row_number() OVER (ORDER BY ve.unidades, ve.cod_vino) AS puesto,
       ve.cod_vino, ve.unidades, v.precio
FROM ventas ve
JOIN vino v ON v.cod_vino = ve.cod_vino
ORDER BY ve.unidades, ve.cod_vino
LIMIT 11;

WITH ventas AS (
    SELECT s.cod_vino, COALESCE(sum(r.cantidad), 0) AS unidades
    FROM (SELECT DISTINCT cod_vino FROM stock_sala) s
    LEFT JOIN renglon_comprobante r ON r.cod_vino = s.cod_vino
    GROUP BY s.cod_vino
),
menos_vendidos AS (
    SELECT cod_vino
    FROM ventas
    ORDER BY unidades, cod_vino
    LIMIT 10
)
UPDATE vino
SET precio = ROUND(precio * 0.85, 2)
WHERE cod_vino IN (SELECT cod_vino FROM menos_vendidos);

SET CONSTRAINTS ALL IMMEDIATE;

-- Control posterior
SELECT cod_vino, precio_anterior, precio_nuevo,
       precio_nuevo = ROUND(precio_anterior * 0.85, 2) AS con_15_por_ciento
FROM auditoria_precio
WHERE fecha_hora = now()
ORDER BY cod_vino;

ROLLBACK;


-- ---------------------------------------------------------------------
-- U6. A los exportadores con más de 3 permisos de exportación, subirles el
-- descuento al 35 %.
--
-- Estrategia: un UPDATE de cliente con una subconsulta que agrupa
-- permiso_exportacion por cliente y conserva los que tienen más de 3
-- (HAVING). No hace falta filtrar por tipo, porque la FK
-- fk_permiso_exportador solo admite permisos de exportadores.
--
-- La condición descuento <> 35 deja afuera a quienes ya tienen el 35 %.
-- El resultado es el mismo, pero no reescribe filas que no cambian, y cada
-- fila reescrita dispara trg_cliente_subtipo, que es caro: revisa toda la
-- tabla cliente.
--
-- Por qué afecta 0 filas sobre el seed: RI-06 ya está cubierta por
-- trg_permiso_descuento, que recalcula el descuento con fn_descuento_cliente
-- cada vez que se agrega o se borra un permiso, y el seed carga el 35 % a
-- esos exportadores. U6 solo corrige descuentos que quedaron mal por otra
-- vía, por ejemplo cambiados a mano: la base no impide modificar
-- cliente.descuento directamente.
--
-- Preparación de la prueba: para ver un cambio real se le baja a mano el
-- descuento al 30 % a un exportador con más de 3 permisos.
--
-- Los comprobantes ya emitidos no cambian: guardan su propio
-- porcentaje_descuento. El nuevo descuento se aplica a las ventas
-- siguientes, o a las anteriores si se ejecuta U1.
--
-- Triggers: trg_cliente_subtipo es diferido; SET CONSTRAINTS ALL IMMEDIATE
-- lo evalúa antes del ROLLBACK.
--
-- Resultado medido:
--   - Sin la preparación: 0 filas afectadas. Los 500 exportadores con más
--     de 3 permisos ya tienen el 35 %.
--   - Con la preparación: 1 fila afectada. El control pasa de 499 con 35 %
--     y 1 con otro valor a 500 con 35 % y 0 con otro valor.
--   - Sin la condición descuento <> 35, la misma sentencia afecta 500 filas
--     y evaluar trg_cliente_subtipo tarda 2,6 s, contra menos de 0,1 s con
--     la condición.
-- ---------------------------------------------------------------------
BEGIN;

-- Control sin preparación
SELECT count(*) AS con_mas_de_3_permisos,
       count(*) FILTER (WHERE c.descuento = 35) AS con_35,
       count(*) FILTER (WHERE c.descuento <> 35) AS con_otro_descuento
FROM cliente c
WHERE c.id_cliente IN (SELECT id_cliente
                       FROM permiso_exportacion
                       GROUP BY id_cliente
                       HAVING count(*) > 3);

-- Preparación: un exportador con más de 3 permisos queda con el 30 %.
UPDATE cliente
SET descuento = 30
WHERE id_cliente = (SELECT id_cliente
                    FROM permiso_exportacion
                    GROUP BY id_cliente
                    HAVING count(*) > 3
                    ORDER BY id_cliente
                    LIMIT 1);

-- Control previo
SELECT count(*) AS con_mas_de_3_permisos,
       count(*) FILTER (WHERE c.descuento = 35) AS con_35,
       count(*) FILTER (WHERE c.descuento <> 35) AS con_otro_descuento
FROM cliente c
WHERE c.id_cliente IN (SELECT id_cliente
                       FROM permiso_exportacion
                       GROUP BY id_cliente
                       HAVING count(*) > 3);

UPDATE cliente
SET descuento = 35
WHERE descuento <> 35
  AND id_cliente IN (SELECT id_cliente
                     FROM permiso_exportacion
                     GROUP BY id_cliente
                     HAVING count(*) > 3);

SET CONSTRAINTS ALL IMMEDIATE;

-- Control posterior
SELECT count(*) AS con_mas_de_3_permisos,
       count(*) FILTER (WHERE c.descuento = 35) AS con_35,
       count(*) FILTER (WHERE c.descuento <> 35) AS con_otro_descuento
FROM cliente c
WHERE c.id_cliente IN (SELECT id_cliente
                       FROM permiso_exportacion
                       GROUP BY id_cliente
                       HAVING count(*) > 3);

ROLLBACK;
