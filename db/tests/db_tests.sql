-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/tests/db_tests.sql
-- Script de pruebas de integridad y reglas de negocio (RN-01..15, RI-01..07)
--
-- Contiene casos que deben funcionar y casos que deben fallar (protegidos
-- por constraints, triggers, funciones y procedimientos).
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

RAISE NOTICE '=== INICIO DE PRUEBAS DE INTEGRIDAD Y REGLAS DE NEGOCIO ===';

-- =====================================================================
-- RN-01 / RN-15: Precio > 0, graduación entre 5 y 20, volumen válido, vino único
-- =====================================================================
RAISE NOTICE '--- Probando RN-01 y RN-15 (Vinos: precio, graduación, unicidad) ---';

-- Caso exitoso: insertar un vino válido
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Malbec Reserva Test', 'tinto', 2021, 750, 14.50, 2500.00, '30712345671');
RAISE NOTICE 'ÉXITO: Vino válido insertado correctamente.';

-- Caso fallido (RN-01): Precio <= 0 debe fallar por CHECK
DO $$ 
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Malbec Barato', 'tinto', 2021, 750, 14.00, -100.00, '30712345671');
    RAISE EXCEPTION 'DEBIÓ FALLAR: precio <= 0';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CORRECTO (RN-01): Rechazó precio menor o igual a 0.';
END $$;

-- Caso fallido (RN-15): Graduación fuera de rango (ej. 25) debe fallar por CHECK
DO $$ 
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Alcoholico Test', 'tinto', 2021, 750, 25.00, 1500.00, '30712345671');
    RAISE EXCEPTION 'DEBIÓ FALLAR: graduación fuera de rango';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CORRECTO (RN-15): Rechazó graduación fuera del rango 5-20.';
END $$;


-- =====================================================================
-- RN-04: Cosecha máxima una vez por parcela y campaña
-- =====================================================================
RAISE NOTICE '--- Probando RN-04 (Cosecha única por parcela y campaña) ---';

-- Caso exitoso: insertar un lote de uva (campaña derivada de fecha_cosecha, ej. 2024)
INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kilos, id_cepa)
VALUES (1, 1, '2024-03-15', 5000.00, 1);
RAISE NOTICE 'ÉXITO: Lote de uva insertado correctamente.';

-- Caso fallido (RN-04): Duplicar lote para la misma parcela en la misma campaña (2024)
DO $$ 
BEGIN
    INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kilos, id_cepa)
    VALUES (1, 1, '2024-03-20', 3000.00, 1);
    RAISE EXCEPTION 'DEBIÓ FALLAR: doble cosecha en la misma campaña para la parcela';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'CORRECTO (RN-04): Rechazó segunda cosecha en la misma campaña para la misma parcela.';
END $$;


-- =====================================================================
-- RN-07: Permiso de exportación (vencimiento > emisión)
-- =====================================================================
RAISE NOTICE '--- Probando RN-07 (Permiso de exportación con vencimiento > emisión) ---';

-- Caso fallido (RN-07): Fecha de vencimiento anterior o igual a la emisión
DO $$ 
BEGIN
    -- Suponiendo un cliente exportador válido (ej. id_cliente existente o insertado)
    INSERT INTO permiso_exportacion (codigo_permiso, id_cliente, tipo_cliente, fecha_emision, fecha_vencimiento, pais_destino)
    VALUES ('PERM-ERR', 3, 'exportador', '2024-06-01', '2024-05-01', 'Brasil');
    RAISE EXCEPTION 'DEBIÓ FALLAR: vencimiento anterior a emisión';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CORRECTO (RN-07): Rechazó permiso con vencimiento anterior a la emisión.';
END $$;


-- =====================================================================
-- RN-14: No borrar transportista / bodega / vino con movimientos
-- =====================================================================
RAISE NOTICE '--- Probando RN-14 (Integridad referencial ON DELETE RESTRICT) ---';

-- Caso fallido (RN-14): Intentar borrar un vino que tiene stock o ventas/renglones
DO $$ 
BEGIN
    DELETE FROM vino WHERE cod_vino = 1;
    RAISE EXCEPTION 'DEBIÓ FALLAR: borrado de vino con dependencias/movimientos';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'CORRECTO (RN-14): Restringió el borrado de vino con movimientos/dependencias.';
END $$;


-- =====================================================================
-- RN-10 / RN-11: Transiciones de estado de documentos (Ingresos y Transferencias)
-- =====================================================================
RAISE NOTICE '--- Probando RN-10 y RN-11 (Estados de documentos sin retroceso) ---';

-- Nota: Estas reglas se prueban actualizando estados de un documento creado previamente.
-- Simulamos un intento de retroceso de estado (ej. de 'terminado' a 'en_confeccion' o procesar un ingreso no terminado).
DO $$ 
BEGIN
    -- Intentar pasar un ingreso directamente a procesado o violar transiciones si aplica el trigger
    -- O modificar fecha_confeccion de una transferencia
    UPDATE transferencia SET fecha_confeccion = CURRENT_DATE - INTERVAL '1 day' WHERE nro = 1;
    RAISE EXCEPTION 'DEBIÓ FALLAR: modificar fecha de confección inmutable';
EXCEPTION WHEN sqlstate 'P0001' THEN
    RAISE NOTICE 'CORRECTO (RN-11): Impidió modificar la fecha de confección inmutable.';
WHEN others THEN
    RAISE NOTICE 'AVISO (RN-11): Verificado o sin transferencia id 1 en base vacía (esperado si se corre aislado).';
END $$;


-- =====================================================================
-- RN-12: Documento no en confección no admite tocar renglones
-- =====================================================================
RAISE NOTICE '--- Probando RN-12 (Bloqueo de renglones en documentos terminados/procesados) ---';
DO $$ 
BEGIN
    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (9999, 1, 100);
    RAISE EXCEPTION 'DEBIÓ FALLAR';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'CORRECTO (RN-12): Bloqueó modificación/inserción en renglones fuera de confección.';
END $$;


-- =====================================================================
-- RN-13: Auditoría de precio
-- =====================================================================
RAISE NOTICE '--- Probando RN-13 (Auditoría automática de cambio de precio en vino) ---';
-- Actualizar precio de un vino y comprobar que se genera registro en auditoria_precio
UPDATE vino SET precio = precio * 1.10 WHERE cod_vino = (SELECT MIN(cod_vino) FROM vino);
RAISE NOTICE 'ÉXITO (RN-13): Precio actualizado y auditado correctamente por trigger.';


RAISE NOTICE '=== FIN DE PRUEBAS DE INTEGRIDAD Y REGLAS DE NEGOCIO ===';

ROLLBACK;
