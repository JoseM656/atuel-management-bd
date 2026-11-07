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
-- Se recorren todos los comprobantes, sin WHERE, porque así lo pide la
-- consigna. La columna total no se escribe en la sentencia, porque RN-08
-- rechaza un total distinto del que surge de los renglones.
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
-- Resultado medido:
--   - Filas afectadas: 150.000. En 83 comprobantes cambia el importe.
--   - Control previo: 83 desactualizados; suma de totales 10.707.050.390,00.
--   - Control posterior: 0 desactualizados; suma de totales 10.706.704.095,00.
--   - Tarda unos 14 s, porque por cada comprobante se ejecutan la función
--     y el trigger que suma sus renglones.
-- ---------------------------------------------------------------------
BEGIN;

-- Preparación: cuarto permiso para el primer exportador con tres permisos
-- y al menos un comprobante.
INSERT INTO permiso_exportacion
SELECT 'PRUEBA-U1', p.id_cliente, CURRENT_DATE, CURRENT_DATE + 365
FROM permiso_exportacion p
WHERE EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = p.id_cliente)
GROUP BY p.id_cliente
HAVING count(*) = 3
ORDER BY p.id_cliente
LIMIT 1;

-- Control previo
SELECT count(*) AS comprobantes,
       count(*) FILTER (WHERE porcentaje_descuento <> fn_descuento_cliente(id_cliente)) AS desactualizados,
       sum(total) AS suma_totales
FROM comprobante;

UPDATE comprobante
SET porcentaje_descuento = fn_descuento_cliente(id_cliente);

-- Control posterior
SELECT count(*) AS comprobantes,
       count(*) FILTER (WHERE porcentaje_descuento <> fn_descuento_cliente(id_cliente)) AS desactualizados,
       sum(total) AS suma_totales
FROM comprobante;

ROLLBACK;
