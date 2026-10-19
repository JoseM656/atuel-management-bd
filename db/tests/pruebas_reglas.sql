-- Una prueba por regla. Todo corre en una transacción y termina en ROLLBACK,
-- así se puede repetir. Cada prueba se deshace sola (subtransacción).
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;   -- los triggers diferidos se evalúan en cada sentencia

-- Ejecuta los pasos previos (deben andar) y espera que el ÚLTIMO falle.
CREATE FUNCTION pg_temp.debe_fallar(p_regla text, p_sql text[]) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE i int; v text;
BEGIN
  BEGIN
    FOR i IN 1 .. array_length(p_sql, 1) - 1 LOOP
      EXECUTE p_sql[i];
    END LOOP;
    BEGIN
      EXECUTE p_sql[array_length(p_sql, 1)];
      v := 'FALLA  ' || p_regla || ' -> la base lo ACEPTÓ';
    EXCEPTION WHEN OTHERS THEN
      v := 'OK     ' || p_regla || ' -> [' || SQLSTATE || '] ' || SQLERRM;
    END;
    RAISE EXCEPTION USING ERRCODE = 'P0999';           -- deshace la prueba
  EXCEPTION
    WHEN SQLSTATE 'P0999' THEN NULL;
    WHEN OTHERS THEN v := 'ERROR  ' || p_regla || ' (preparación): ' || SQLERRM;
  END;
  RETURN v;
END $$;

-- Ejecuta los pasos (deben andar) y evalúa una condición booleana final.
CREATE FUNCTION pg_temp.debe_funcionar(p_regla text, p_sql text[], p_check text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE i int; ok boolean; v text;
BEGIN
  BEGIN
    FOR i IN 1 .. array_length(p_sql, 1) LOOP
      EXECUTE p_sql[i];
    END LOOP;
    EXECUTE p_check INTO ok;
    v := CASE WHEN ok THEN 'OK     ' ELSE 'FALLA  ' END || p_regla
         || CASE WHEN ok THEN '' ELSE ' -> no se cumple: ' || p_check END;
    RAISE EXCEPTION USING ERRCODE = 'P0999';
  EXCEPTION
    WHEN SQLSTATE 'P0999' THEN NULL;
    WHEN OTHERS THEN v := 'FALLA  ' || p_regla || ' -> error inesperado: ' || SQLERRM;
  END;
  RETURN v;
END $$;

CREATE TEMP TABLE resultado (n serial, r text);

INSERT INTO resultado (r) VALUES
-- RN-01 precio > 0
(pg_temp.debe_fallar('RN-01 precio 0', ARRAY[$q$UPDATE vino SET precio = 0 WHERE cod_vino = 1$q$])),
-- RN-02 sala en localidad existente / encargado único
(pg_temp.debe_fallar('RN-02 sala con localidad inexistente', ARRAY[$q$INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES ('X', 1, 'lunes', 999)$q$])),
(pg_temp.debe_fallar('RN-02 mismo encargado en 2 localidades', ARRAY[$q$UPDATE localidad SET cuit_encargado = '20111111111' WHERE id_localidad = 2$q$])),
-- RN-03 empleado sin sala
(pg_temp.debe_fallar('RN-03 empleado sin sala', ARRAY[$q$INSERT INTO empleado VALUES ('20333333333', 'X', '2020-01-01', 1000, NULL)$q$])),
-- RN-04 una cosecha por parcela y campaña
(pg_temp.debe_fallar('RN-04 dos cosechas en 2024', ARRAY[
   $q$INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kg, cuit_bodega) VALUES (1, 1, '2024-03-01', 1000, '30111111111')$q$,
   $q$INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kg, cuit_bodega) VALUES (1, 1, '2024-04-10', 900, '30111111111')$q$])),
(pg_temp.debe_funcionar('RN-04 cosechas en años distintos', ARRAY[
   $q$INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kg, cuit_bodega) VALUES (1, 1, '2024-03-01', 1000, '30111111111')$q$,
   $q$INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kg, cuit_bodega) VALUES (1, 1, '2025-03-01', 900, '30111111111')$q$],
   $q$SELECT count(*) = 2 FROM lote_uva$q$)),
-- RN-05 suma de cortes = 100
(pg_temp.debe_fallar('RN-05 composición suma 95', ARRAY[$q$UPDATE composicion SET porcentaje = 80 WHERE cod_vino = 1 AND id_cepa = 1$q$])),
(pg_temp.debe_funcionar('RN-05 cambiar corte a 80/20', ARRAY[
   $q$SET CONSTRAINTS trg_composicion_suma_100 DEFERRED$q$,
   $q$UPDATE composicion SET porcentaje = 80 WHERE cod_vino = 1 AND id_cepa = 1$q$,
   $q$UPDATE composicion SET porcentaje = 20 WHERE cod_vino = 1 AND id_cepa = 2$q$,
   $q$SET CONSTRAINTS ALL IMMEDIATE$q$],
   $q$SELECT sum(porcentaje) = 100 FROM composicion WHERE cod_vino = 1$q$)),
-- RN-06 descuento por tipo
(pg_temp.debe_funcionar('RN-06 descuentos 10/20/30', ARRAY[$q$SELECT 1$q$],
   $q$SELECT array_agg(descuento ORDER BY id_cliente) = ARRAY[10,20,30]::numeric[] FROM cliente$q$)),
(pg_temp.debe_fallar('RN-06 descuento 50 a mano', ARRAY[$q$UPDATE cliente SET descuento = 50 WHERE id_cliente = 1$q$])),
(pg_temp.debe_funcionar('RI-06 exportador con 4 permisos -> 35', ARRAY[
   $q$INSERT INTO permiso_exportacion VALUES ('P1', 3, '2025-01-01', '2027-01-01'), ('P2', 3, '2025-01-01', '2027-01-01'), ('P3', 3, '2025-01-01', '2027-01-01'), ('P4', 3, '2025-01-01', '2027-01-01')$q$],
   $q$SELECT descuento = 35 FROM cliente WHERE id_cliente = 3$q$)),
-- RN-07 vencimiento > emisión
(pg_temp.debe_fallar('RN-07 vence antes de emitirse', ARRAY[$q$INSERT INTO permiso_exportacion VALUES ('PX', 3, '2025-05-01', '2025-01-01')$q$])),
-- RN-08 total calculado por la base (distribuidor 20 %: 2 x 12500 x 0,8 = 20000)
(pg_temp.debe_funcionar('RN-08 total de una venta', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala, total) VALUES (2, 1, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$],
   $q$SELECT subtotal = 25000 AND total = 20000 FROM comprobante ORDER BY nro DESC LIMIT 1$q$)),
(pg_temp.debe_fallar('RN-08 pisar el total a mano', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$UPDATE comprobante SET total = 1 WHERE nro = (SELECT max(nro) FROM comprobante)$q$])),
(pg_temp.debe_fallar('RN-08 pisar el subtotal a mano', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$UPDATE comprobante SET subtotal = 1 WHERE nro = (SELECT max(nro) FROM comprobante)$q$])),
(pg_temp.debe_funcionar('RN-08 U1: cambiar el descuento recalcula el total', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$UPDATE comprobante SET porcentaje_descuento = 10 WHERE nro = (SELECT max(nro) FROM comprobante)$q$],
   $q$SELECT total = 22500 FROM comprobante ORDER BY nro DESC LIMIT 1$q$)),
(pg_temp.debe_funcionar('RN-08 U1: escribir el total correcto se acepta', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$UPDATE comprobante SET total = fn_total_comprobante(nro) WHERE nro = (SELECT max(nro) FROM comprobante)$q$],
   $q$SELECT total = 20000 FROM comprobante ORDER BY nro DESC LIMIT 1$q$)),
(pg_temp.debe_fallar('RN-08 borrar un renglón suelto', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$DELETE FROM renglon_comprobante WHERE nro = (SELECT max(nro) FROM comprobante)$q$])),
(pg_temp.debe_fallar('RN-08 cambiar la cantidad de un renglón vendido', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$UPDATE renglon_comprobante SET cantidad = 1 WHERE nro = (SELECT max(nro) FROM comprobante)$q$])),
(pg_temp.debe_fallar('RN-08 pisar el subtotal de un renglón', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$UPDATE renglon_comprobante SET subtotal = 1 WHERE nro = (SELECT max(nro) FROM comprobante)$q$])),
(pg_temp.debe_funcionar('RN-08 U1: el nuevo descuento llega a los renglones', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (2, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2), ((SELECT max(nro) FROM comprobante), 2, 1)$q$,
   $q$UPDATE comprobante SET porcentaje_descuento = 10 WHERE nro = (SELECT max(nro) FROM comprobante)$q$],
   $q$SELECT c.total = SUM(r.subtotal) AND SUM(r.importe_descuento) = 3300 FROM comprobante c JOIN renglon_comprobante r USING (nro) WHERE c.nro = (SELECT max(nro) FROM comprobante) GROUP BY c.total$q$)),
(pg_temp.debe_funcionar('D1 borrar un comprobante no devuelve stock', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (1, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 2)$q$,
   $q$DELETE FROM comprobante WHERE nro = (SELECT max(nro) FROM comprobante)$q$],
   $q$SELECT fn_stock_sala(1, 1) = 3$q$)),
-- RN-09 stock
(pg_temp.debe_fallar('RN-09 vender 2 con stock 1', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (1, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 2, 2)$q$])),
(pg_temp.debe_funcionar('RN-09 vender todo el stock deja 0', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (1, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 5)$q$],
   $q$SELECT fn_stock_sala(1, 1) = 0$q$)),
(pg_temp.debe_fallar('RN-09 stock negativo a mano', ARRAY[$q$UPDATE stock_sala SET cantidad = -1 WHERE id_sala = 1 AND cod_vino = 1$q$])),
-- RN-10 ingresos
(pg_temp.debe_fallar('RN-10 procesar ingreso en confección', ARRAY[$q$CALL sp_procesar_ingreso(1)$q$])),
(pg_temp.debe_funcionar('RN-10 procesar ingreso terminado', ARRAY[$q$CALL sp_procesar_ingreso(2)$q$],
   $q$SELECT (SELECT cantidad FROM stock_deposito WHERE cod_vino = 2) = 55 AND (SELECT estado FROM ingreso WHERE cod_ingreso = 2) = 'procesado'$q$)),
(pg_temp.debe_fallar('RN-10 retroceder terminado -> en_confeccion', ARRAY[$q$UPDATE ingreso SET estado = 'en_confeccion' WHERE cod_ingreso = 2$q$])),
(pg_temp.debe_fallar('RN-10 saltar en_confeccion -> procesado', ARRAY[$q$UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 1$q$])),
(pg_temp.debe_fallar('RN-10 crear ingreso ya procesado', ARRAY[$q$INSERT INTO ingreso (cod_transportista, cuit_bodega, estado) VALUES (1, '30111111111', 'procesado')$q$])),
(pg_temp.debe_fallar('RN-11 crear transferencia ya terminada', ARRAY[$q$INSERT INTO transferencia (id_sala, estado) VALUES (1, 'terminado')$q$])),
(pg_temp.debe_funcionar('RN-10 un ingreso nuevo nace en confección', ARRAY[$q$INSERT INTO ingreso (cod_transportista, cuit_bodega) VALUES (1, '30111111111')$q$],
   $q$SELECT estado = 'en_confeccion' FROM ingreso ORDER BY cod_ingreso DESC LIMIT 1$q$)),
(pg_temp.debe_fallar('RN-10 pasar a procesado sin el procedimiento', ARRAY[$q$UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 2$q$])),
-- RN-11 transferencias
(pg_temp.debe_fallar('RN-11 pasar a procesado sin el procedimiento', ARRAY[$q$UPDATE transferencia SET estado = 'procesado' WHERE nro = 3$q$])),
(pg_temp.debe_fallar('RN-10 la marca no queda activa después del CALL', ARRAY[
   $q$CALL sp_procesar_transferencia(3)$q$,
   $q$UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 2$q$])),
(pg_temp.debe_fallar('RN-11 procesar sin stock suficiente', ARRAY[$q$CALL sp_procesar_transferencia(2)$q$])),
(pg_temp.debe_funcionar('RN-11 sin stock no deja nada a medias', ARRAY[
   $q$DO $d$ BEGIN CALL sp_procesar_transferencia(2); EXCEPTION WHEN OTHERS THEN NULL; END $d$$q$],
   $q$SELECT (SELECT cantidad FROM stock_deposito WHERE cod_vino = 1) = 100 AND fn_stock_sala(1, 1) = 5 AND (SELECT estado FROM transferencia WHERE nro = 2) = 'terminado'$q$)),
(pg_temp.debe_funcionar('RN-11 procesar transferencia OK', ARRAY[$q$CALL sp_procesar_transferencia(3)$q$],
   $q$SELECT fn_stock_sala(2, 2) = 5 AND (SELECT cantidad FROM stock_deposito WHERE cod_vino = 2) = 45$q$)),
(pg_temp.debe_funcionar('RN-11 fecha de confección forzada a hoy', ARRAY[$q$INSERT INTO transferencia (id_sala, fecha_confeccion) VALUES (1, '2020-01-01')$q$],
   $q$SELECT fecha_confeccion = CURRENT_DATE FROM transferencia ORDER BY nro DESC LIMIT 1$q$)),
(pg_temp.debe_fallar('RN-11 modificar fecha de confección', ARRAY[$q$UPDATE transferencia SET fecha_confeccion = '2020-01-01' WHERE nro = 1$q$])),
-- RN-12 renglones bloqueados
(pg_temp.debe_fallar('RN-12 agregar renglón a transferencia terminada', ARRAY[$q$INSERT INTO renglon_transferencia VALUES (3, 1, 1)$q$])),
(pg_temp.debe_fallar('RN-12 borrar renglón de ingreso terminado', ARRAY[$q$DELETE FROM renglon_ingreso WHERE cod_ingreso = 2$q$])),
(pg_temp.debe_funcionar('RN-12 editar renglón en confección', ARRAY[$q$UPDATE renglon_ingreso SET cantidad = 20 WHERE cod_ingreso = 1$q$],
   $q$SELECT cantidad = 20 FROM renglon_ingreso WHERE cod_ingreso = 1$q$)),
-- RN-13 auditoría
(pg_temp.debe_funcionar('RN-13 cambio de precio auditado', ARRAY[$q$UPDATE vino SET precio = 13000 WHERE cod_vino = 1$q$],
   $q$SELECT count(*) = 1 FROM auditoria_precio WHERE cod_vino = 1 AND precio_anterior = 12500 AND precio_nuevo = 13000 AND usuario = current_user$q$)),
-- RN-14 borrado con movimientos
(pg_temp.debe_fallar('RN-14 borrar transportista con ingresos', ARRAY[$q$DELETE FROM transportista WHERE cod_transportista = 1$q$])),
(pg_temp.debe_fallar('RN-14 borrar bodega con vinos', ARRAY[$q$DELETE FROM bodega WHERE cuit = '30111111111'$q$])),
(pg_temp.debe_fallar('RN-14 borrar vino con movimientos', ARRAY[$q$DELETE FROM vino WHERE cod_vino = 1$q$])),
-- RN-15 positivos y graduación
(pg_temp.debe_fallar('RN-15 graduación 25', ARRAY[$q$UPDATE vino SET graduacion = 25 WHERE cod_vino = 1$q$])),
(pg_temp.debe_fallar('RN-15 cantidad 0 en renglón', ARRAY[$q$INSERT INTO renglon_ingreso VALUES (1, 2, 0)$q$])),
(pg_temp.debe_fallar('RN-15 kilos negativos', ARRAY[$q$INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kg, cuit_bodega) VALUES (1, 1, '2024-03-01', -5, '30111111111')$q$])),
-- Reglas implícitas
(pg_temp.debe_fallar('RI-04 vino de otra bodega en el ingreso', ARRAY[$q$INSERT INTO renglon_ingreso VALUES (1, 3, 5)$q$])),
(pg_temp.debe_fallar('RI-05 transportista que no cubre el depósito', ARRAY[$q$INSERT INTO ingreso (cod_transportista, cuit_bodega) VALUES (2, '30111111111')$q$])),
(pg_temp.debe_fallar('RI-02 vino sin maridaje', ARRAY[$q$INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES ('Sin Maridaje', 'tinto', 2022, 750, 13, 5000, '30111111111')$q$])),
(pg_temp.debe_fallar('Jerarquía: cliente sin subtipo', ARRAY[$q$INSERT INTO cliente (nombre_razon_social, tipo_doc, nro_doc, direccion, id_localidad, tipo, descuento) VALUES ('Z', 'DNI', '1', 'D', 1, 'socio', 0)$q$])),
-- Consignas de la sección 8 que dependen de las reglas
(pg_temp.debe_funcionar('D5 borrar un ingreso (cascade a renglones)', ARRAY[$q$DELETE FROM ingreso WHERE cod_ingreso = 1$q$],
   $q$SELECT NOT EXISTS (SELECT 1 FROM ingreso WHERE cod_ingreso = 1)$q$)),
(pg_temp.debe_funcionar('D5 borrar un ingreso terminado entero', ARRAY[$q$DELETE FROM ingreso WHERE cod_ingreso = 2$q$],
   $q$SELECT NOT EXISTS (SELECT 1 FROM renglon_ingreso WHERE cod_ingreso = 2)$q$)),
(pg_temp.debe_funcionar('Borrar una transferencia terminada entera', ARRAY[$q$DELETE FROM transferencia WHERE nro = 3$q$],
   $q$SELECT NOT EXISTS (SELECT 1 FROM renglon_transferencia WHERE nro = 3)$q$)),
(pg_temp.debe_funcionar('D1 borrar un comprobante (cascade a renglones)', ARRAY[
   $q$INSERT INTO comprobante (id_cliente, id_sala) VALUES (1, 1)$q$,
   $q$INSERT INTO renglon_comprobante (nro, cod_vino, cantidad) VALUES ((SELECT max(nro) FROM comprobante), 1, 1)$q$,
   $q$DELETE FROM comprobante WHERE nro = (SELECT max(nro) FROM comprobante)$q$],
   $q$SELECT true$q$));

SELECT r AS resultado FROM resultado ORDER BY n;
ROLLBACK;
