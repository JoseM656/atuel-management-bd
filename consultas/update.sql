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
