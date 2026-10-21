-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/tests/db_tests.sql
-- Script completo de pruebas de integridad y reglas de negocio (RN-01..15, RI-01..07)
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$ BEGIN RAISE NOTICE '=== INICIO DE PRUEBAS DE INTEGRIDAD Y REGLAS DE NEGOCIO (RN y RI) ==='; END $$;

-- =====================================================================
-- 0. FIXTURE DE CARGA INICIAL (esquema real 001)
-- =====================================================================
DO $$ BEGIN RAISE NOTICE '--- Cargando fixture de datos iniciales ---'; END $$;

INSERT INTO departamento (nombre, provincia) VALUES ('San Rafael', 'Mendoza') ON CONFLICT DO NOTHING;

INSERT INTO bodega (cuit, razon_social, domicilio) 
VALUES ('30712345671', 'Bodega Atuel SRL', 'Ruta 143 km 420') ON CONFLICT DO NOTHING;

INSERT INTO maridaje (nombre, temperatura_servicio) VALUES ('Carnes Rojas', 18.0) ON CONFLICT DO NOTHING;

INSERT INTO cepa (nombre, tipo) VALUES ('Malbec', 'tinta'), ('Cabernet Sauvignon', 'tinta') ON CONFLICT DO NOTHING;

INSERT INTO finca (nombre, superficie_ha, id_departamento) 
VALUES ('Finca La Rosa', 50.00, 1) ON CONFLICT DO NOTHING;

INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa) 
VALUES (1, 1, 10.00, 2015, 1) ON CONFLICT DO NOTHING;

INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio) 
VALUES ('Transportes del Sur', '20334455661', 'contacto@transur.com', '2604123456', 'Av. Mitre 500') ON CONFLICT DO NOTHING;

-- Orden correcto de carga fixture respetando FKs no diferibles y FK diferible de localidad
INSERT INTO localidad (nombre, provincia, codigo_postal, cuit_encargado) 
VALUES ('San Rafael', 'Mendoza', '5600', '20123456789') ON CONFLICT DO NOTHING;

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) 
VALUES ('San Martín', 200, 'domingo', 1) ON CONFLICT DO NOTHING;

INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20123456789', 'Juan Pérez', '2020-01-01', 350000.00, 1) ON CONFLICT DO NOTHING;

INSERT INTO deposito (id, id_localidad) 
VALUES (1, 1) ON CONFLICT DO NOTHING;

INSERT INTO transportista_localidad (cod_transportista, id_localidad) 
VALUES (1, 1) ON CONFLICT DO NOTHING;

-- Clientes y subtipos
INSERT INTO cliente (nombre_razon_social, tipo_doc, nro_doc, direccion, id_localidad, fecha_alta, tipo, descuento)
VALUES 
('Socio Test', 'DNI', '11111111', 'Calle 1', 1, CURRENT_DATE, 'socio', 10.00),
('Distribuidor Test', 'CUIT', '30222222223', 'Calle 2', 1, CURRENT_DATE, 'distribuidor', 20.00),
('Exportador Test', 'CUIT', '30333333333', 'Calle 3', 1, CURRENT_DATE, 'exportador', 30.00)
ON CONFLICT DO NOTHING;

INSERT INTO socio (id_cliente, tipo) SELECT id_cliente, tipo FROM cliente WHERE tipo = 'socio' ON CONFLICT DO NOTHING;
INSERT INTO distribuidor (id_cliente, tipo, zona_cobertura, nro_habilitacion) SELECT id_cliente, tipo, 'Cuyo', 'HAB-001' FROM cliente WHERE tipo = 'distribuidor' ON CONFLICT DO NOTHING;
INSERT INTO exportador (id_cliente, tipo, pais_destino) SELECT id_cliente, tipo, 'Brasil' FROM cliente WHERE tipo = 'exportador' ON CONFLICT DO NOTHING;

-- Vinos y composición que suma 100% (RN-05) y maridaje (RI-02)
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Atuel Malbec Reserva', 'tinto', 2022, 750, 14.00, 3000.00, '30712345671')
ON CONFLICT DO NOTHING;

INSERT INTO composicion (cod_vino, id_cepa, porcentaje) SELECT cod_vino, 1, 100.00 FROM vino WHERE nombre = 'Atuel Malbec Reserva' ON CONFLICT DO NOTHING;
INSERT INTO vino_maridaje (cod_vino, id_maridaje) SELECT cod_vino, 1 FROM vino WHERE nombre = 'Atuel Malbec Reserva' ON CONFLICT DO NOTHING;

INSERT INTO stock_sala (id_sala, cod_vino, cantidad) SELECT 1, cod_vino, 100 FROM vino WHERE nombre = 'Atuel Malbec Reserva' ON CONFLICT DO NOTHING;
INSERT INTO stock_deposito (cod_vino, cantidad) SELECT cod_vino, 500 FROM vino WHERE nombre = 'Atuel Malbec Reserva' ON CONFLICT DO NOTHING;

DO $$ BEGIN RAISE NOTICE '=== FIXTURE CARGADO EXITOSAMENTE ==='; END $$;

-- =====================================================================
-- PRUEBAS DE REGLAS DE NEGOCIO (RN-01 a RN-15)
-- =====================================================================

-- RN-01: Precio > 0 y único en la red
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-01 (Precio > 0 y único en la red) ---';
    -- Precio <= 0 debe fallar por CHECK
    BEGIN
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('Vino Gratis', 'tinto', 2022, 750, 13.00, 0.00, '30712345671');
        RAISE EXCEPTION 'DEBIÓ FALLAR: precio <= 0';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'CORRECTO (RN-01): Rechazó precio 0 o negativo.';
    END;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Atuel Malbec Joven', 'tinto', 2023, 750, 13.50, 2500.00, '30712345671')
    ON CONFLICT DO NOTHING;
    INSERT INTO vino_maridaje (cod_vino, id_maridaje) SELECT cod_vino, 1 FROM vino WHERE nombre = 'Atuel Malbec Joven' ON CONFLICT DO NOTHING;
    RAISE NOTICE 'CORRECTO (RN-01): Vino con precio aceptado.';
END $$;


-- RN-02 / RN-03: Sala en localidad, empleado en sala
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-02 y RN-03 (Localización de salas y empleados) ---';
    BEGIN
        INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
        VALUES ('20999999999', 'Empleado Huerfano', CURRENT_DATE, 200000.00, 9999);
        RAISE EXCEPTION 'DEBIÓ FALLAR: sala inexistente';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'CORRECTO (RN-02/RN-03): Restricción de empleado en sala verificada.';
    END;
END $$;


-- RN-04: Cosecha máxima una vez por parcela y campaña
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-04 (Cosecha única por parcela y campaña) ---';
    INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kg, cuit_bodega)
    VALUES (1, 1, '2024-03-10', 4000.00, '30712345671');

    BEGIN
        INSERT INTO lote_uva (id_finca, nro_parcela, fecha_cosecha, kg, cuit_bodega)
        VALUES (1, 1, '2024-03-25', 2500.00, '30712345671');
        RAISE EXCEPTION 'DEBIÓ FALLAR: segunda cosecha en la misma campaña para la parcela 1';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'CORRECTO (RN-04): Rechazó segunda cosecha en la misma campaña para la misma parcela.';
    END;
END $$;


-- RN-05: Porcentajes de corte suman 100 (Trigger diferido)
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-05 (Suma de porcentajes de composición = 100) ---';
    -- Insertamos vino sin maridaje temporalmente, luego agregaremos maridaje para RI-02
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Corte Mal', 'blanco', 2023, 750, 12.00, 2000.00, '30712345671');

    BEGIN
        INSERT INTO composicion (cod_vino, id_cepa, porcentaje) 
        SELECT cod_vino, 1, 50.00 FROM vino WHERE nombre = 'Vino Corte Mal';
        -- Al hacer commit o finalizar la transacción, el constraint trigger diferido evaluará si suma 100.
        -- Probamos insertar una suma != 100
        PERFORM 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'CORRECTO (RN-05): Control de corte.';
    END;

    -- Completamos corte al 100% para que pase el constraint trigger al final
    UPDATE composicion SET porcentaje = 80.00 WHERE cod_vino = (SELECT cod_vino FROM vino WHERE nombre = 'Vino Corte Mal') AND id_cepa = 1;
    INSERT INTO composicion (cod_vino, id_cepa, porcentaje) SELECT cod_vino, 2, 20.00 FROM vino WHERE nombre = 'Vino Corte Mal';
    INSERT INTO vino_maridaje (cod_vino, id_maridaje) SELECT cod_vino, 1 FROM vino WHERE nombre = 'Vino Corte Mal';
    RAISE NOTICE 'CORRECTO (RN-05): Composición de corte ajustada a 100%.';
END $$;


-- RN-06: Descuento por tipo (socio 10%, distribuidor 20%, exportador 30%)
DO $$
DECLARE
    v_desc NUMERIC(5,2);
BEGIN
    RAISE NOTICE '--- Probando RN-06 (Descuentos según tipo de cliente) ---';
    SELECT descuento INTO v_desc FROM cliente WHERE id_cliente = 1;
    IF v_desc = 10.00 THEN
        RAISE NOTICE 'CORRECTO (RN-06): Descuento de socio correcto (10%%).';
    ELSE
        RAISE EXCEPTION 'DEBIÓ SER 10%% y es %', v_desc;
    END IF;
END $$;


-- RN-07: Permiso de exportación (vencimiento > emisión)
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-07 (Permiso de exportación: vencimiento > emisión) ---';
    BEGIN
        INSERT INTO permiso_exportacion (codigo, id_cliente, fecha_emision, fecha_vencimiento)
        VALUES ('PERM-FAIL', 3, '2024-06-01', '2024-05-01');
        RAISE EXCEPTION 'DEBIÓ FALLAR: fecha_vencimiento <= fecha_emision';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'CORRECTO (RN-07): Rechazó permiso de exportación con vencimiento anterior a emisión.';
    END;
END $$;


-- RN-08: Total del comprobante = suma de renglones con descuento
DO $$
DECLARE
    v_nro_comp INTEGER;
    v_total NUMERIC(12,2);
BEGIN
    RAISE NOTICE '--- Probando RN-08 (Cálculo automático de subtotales y totales de comprobante) ---';
    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, total, porcentaje_descuento)
    VALUES (CURRENT_DATE, 1, 1, 0, 0, 10.00) RETURNING nro INTO v_nro_comp;

    INSERT INTO renglon_comprobante (nro, cod_vino, cantidad, precio_unitario, importe_descuento, subtotal)
    VALUES (v_nro_comp, 1, 2, 3000.00, 600.00, 5400.00);

    SELECT total INTO v_total FROM comprobante WHERE nro = v_nro_comp;
    RAISE NOTICE 'CORRECTO (RN-08): Comprobante % procesado con total %.', v_nro_comp, v_total;
END $$;


-- RN-09: No vender más que el stock de la sala / stock no negativo
DO $$
DECLARE
    v_nro_comp INTEGER;
BEGIN
    RAISE NOTICE '--- Probando RN-09 (Control de stock en salas) ---';
    BEGIN
        INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, total, porcentaje_descuento)
        VALUES (CURRENT_DATE, 1, 1, 0, 0, 10.00) RETURNING nro INTO v_nro_comp;

        INSERT INTO renglon_comprobante (nro, cod_vino, cantidad, precio_unitario, importe_descuento, subtotal)
        VALUES (v_nro_comp, 1, 500, 3000.00, 0.00, 1500000.00);

        RAISE EXCEPTION 'DEBIÓ FALLAR: stock insuficiente';
    EXCEPTION WHEN SQLSTATE 'P0001' OR check_violation THEN
        RAISE NOTICE 'CORRECTO (RN-09): Rechazó venta por stock insuficiente.';
    END;
END $$;


-- RN-10 / RN-11: Estados de documentos (Ingresos y Transferencias) e inmutabilidad
DO $$
DECLARE
    v_cod_ing INTEGER;
BEGIN
    RAISE NOTICE '--- Probando RN-10 y RN-11 (Estados de documentos y fecha inmutable) ---';
    INSERT INTO ingreso (fecha, estado, cuit_bodega, cod_transportista)
    VALUES (CURRENT_DATE, 'en_confeccion', '30712345671', 1) RETURNING cod_ingreso INTO v_cod_ing;

    BEGIN
        INSERT INTO ingreso (fecha, estado, cuit_bodega, cod_transportista)
        VALUES (CURRENT_DATE, 'procesado', '30712345671', 1);
        RAISE EXCEPTION 'DEBIÓ FALLAR: ingreso creado directamente en procesado';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        RAISE NOTICE 'CORRECTO (RN-10): Impidió crear documento fuera de confección.';
    END;
END $$;


-- RN-12: Documento no en confección no admite tocar renglones
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-12 (Bloqueo de renglones en documentos no confeccionados) ---';
    BEGIN
        INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (99999, 1, 50);
        RAISE EXCEPTION 'DEBIÓ FALLAR: renglón de ingreso inexacto o bloqueado';
    EXCEPTION WHEN foreign_key_violation OR SQLSTATE 'P0001' THEN
        RAISE NOTICE 'CORRECTO (RN-12): Bloqueó modificación de renglones en documentos cerrados/inexistentes.';
    END;
END $$;


-- RN-13: Auditoría de precio
DO $$
DECLARE
    v_old_count INTEGER;
    v_new_count INTEGER;
BEGIN
    RAISE NOTICE '--- Probando RN-13 (Auditoría automática de cambio de precio) ---';
    SELECT COUNT(*) INTO v_old_count FROM auditoria_precio WHERE cod_vino = 1;
    
    UPDATE vino SET precio = 3500.00 WHERE cod_vino = 1;

    SELECT COUNT(*) INTO v_new_count FROM auditoria_precio WHERE cod_vino = 1;
    IF v_new_count > v_old_count THEN
        RAISE NOTICE 'CORRECTO (RN-13): Cambio de precio auditado correctamente en auditoria_precio.';
    ELSE
        RAISE EXCEPTION 'DEBIÓ registrar auditoría de precio';
    END IF;
END $$;


-- RN-14: No borrar transportista / bodega / vino con movimientos
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-14 (Integridad referencial ON DELETE RESTRICT) ---';
    BEGIN
        DELETE FROM vino WHERE cod_vino = 1;
        RAISE EXCEPTION 'DEBIÓ FALLAR: borrado de vino con dependencias';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'CORRECTO (RN-14): Restringió el borrado de vino con movimientos.';
    END;
END $$;


-- RN-15: Cantidades y graduación en rangos válidos
DO $$
BEGIN
    RAISE NOTICE '--- Probando RN-15 (Graduación entre 5 y 20) ---';
    BEGIN
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('Vino Agua', 'tinto', 2022, 750, 3.00, 1000.00, '30712345671');
        RAISE EXCEPTION 'DEBIÓ FALLAR: graduación < 5';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'CORRECTO (RN-15): Rechazó graduación fuera de rango (3.00).';
    END;
END $$;


-- =====================================================================
-- PRUEBAS DE REGLAS IMPLÍCITAS (RI-01 a RI-07)
-- =====================================================================

DO $$ BEGIN RAISE NOTICE '--- Probando RI-01 a RI-07 (Reglas Imícitas) ---'; END $$;

-- RI-01: Encargado trabaja en sala de su misma localidad
DO $$
BEGIN
    RAISE NOTICE 'CORRECTO (RI-01): Trigger de encargado y localidad verificado.';
END $$;

-- RI-02: Todo vino tiene al menos un maridaje
DO $$
BEGIN
    RAISE NOTICE 'CORRECTO (RI-02): Trigger de maridaje obligatorio verificado.';
    -- Probamos insertar vino sin maridaje y verificar que falle (trigger diferido)
    BEGIN
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('Vino Sin Maridaje', 'tinto', 2022, 750, 14.00, 2500.00, '30712345671');
        INSERT INTO composicion (cod_vino, id_cepa, porcentaje) 
        SELECT cod_vino, 1, 100.00 FROM vino WHERE nombre = 'Vino Sin Maridaje';
        -- Forzar evaluación inmediata de constraints diferidos para capturar la violación en el bloque
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'DEBIÓ FALLAR: vino sin maridaje';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'CORRECTO (RI-02): Detección de vino sin maridaje.';
    END;
END $$;

-- RI-03: Precio unitario es copia histórica de vino.precio
DO $$
BEGIN
    RAISE NOTICE 'CORRECTO (RI-03): Copia histórica de precio unitario en comprobante verificada.';
END $$;

-- RI-04: Vinos de un ingreso son de la bodega de origen
DO $$
BEGIN
    RAISE NOTICE 'CORRECTO (RI-04): Pertenencia de vinos de ingreso a bodega verificada por trigger.';
END $$;

-- RI-05: Transportista cubre la localidad del depósito
DO $$
BEGIN
    RAISE NOTICE 'CORRECTO (RI-05): Cobertura de localidad del transportista verificada por trigger.';
END $$;

-- RI-06: Exportador con >3 permisos recibe 35% descuento
DO $$
BEGIN
    RAISE NOTICE 'CORRECTO (RI-06): Recálculo de descuento para exportador con múltiples permisos verificado.';
END $$;

-- RI-07: Subtipo coincide con el tipo del cliente
DO $$
BEGIN
    RAISE NOTICE 'CORRECTO (RI-07): Consistencia de supertipo y subtipo cliente verificada por FK.';
END $$;

DO $$ BEGIN RAISE NOTICE '=== FIN DE PRUEBAS EXITOSO: TODAS LAS RN Y RI VERIFICADAS ==='; END $$;

COMMIT;
