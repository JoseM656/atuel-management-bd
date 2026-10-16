-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/004_procedimientos.sql
-- Etapa 2: procedimientos transaccionales (PostgreSQL 14+)
--
--   sp_procesar_ingreso      -> RN-10: solo un ingreso 'terminado' impacta
--                               el stock del depósito y pasa a 'procesado'.
--   sp_procesar_transferencia -> RN-11: solo una transferencia 'terminado'
--                               descuenta del depósito, suma a la sala y
--                               pasa a 'procesado'.
--
-- Decisiones de diseño:
--   * NO emiten COMMIT/ROLLBACK: corren dentro de la transacción del
--     llamador (CALL en psql o transacción en la API). Cualquier
--     RAISE EXCEPTION revierte todos los cambios hechos hasta ese punto.
--   * Bloquean con FOR UPDATE: la cabecera del documento (evita doble
--     procesamiento concurrente) y, en transferencias, cada fila de
--     stock_deposito (sobreventa / demo de concurrencia).
--   * Anexo A.6: un vino sin fila en stock_deposito o con stock insuficiente
--     lanza excepción (no pasa en silencio).
--   * Renglones recorridos en orden por cod_vino para evitar deadlocks.
--   * UPSERT (ON CONFLICT) para crear o sumar en stock_deposito / stock_sala.
--
-- Se aplica después de 001, 002 y 003, sobre la misma base.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- sp_procesar_ingreso
-- Propósito: procesar un ingreso 'terminado': suma sus renglones al stock
--   del depósito central y lo marca 'procesado' (RN-10).
-- Parámetros: p_cod_ingreso INTEGER.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod_ingreso INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    r        RECORD;
BEGIN
    SELECT estado INTO v_estado
    FROM ingreso
    WHERE cod_ingreso = p_cod_ingreso
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ingreso % no existe', p_cod_ingreso;
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'ingreso % en estado %, solo se procesa terminado',
            p_cod_ingreso, v_estado;
    END IF;

    FOR r IN
        SELECT cod_vino, cantidad
        FROM renglon_ingreso
        WHERE cod_ingreso = p_cod_ingreso
        ORDER BY cod_vino
    LOOP
        INSERT INTO stock_deposito (cod_vino, cantidad)
        VALUES (r.cod_vino, r.cantidad)
        ON CONFLICT (cod_vino)
        DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;
    END LOOP;

    UPDATE ingreso
    SET estado = 'procesado'
    WHERE cod_ingreso = p_cod_ingreso;
END;
$$;

-- ---------------------------------------------------------------------
-- sp_procesar_transferencia
-- Propósito: procesar una transferencia 'terminado': descuenta del depósito
--   y suma al stock de la sala, y la marca 'procesado' (RN-11).
-- Parámetros: p_nro INTEGER.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sala INTEGER;
    v_estado  estado_documento;
    v_stock   INTEGER;
    r         RECORD;
BEGIN
    SELECT id_sala, estado INTO v_id_sala, v_estado
    FROM transferencia
    WHERE nro = p_nro
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'transferencia % no existe', p_nro;
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'transferencia % en estado %, solo se procesa terminado',
            p_nro, v_estado;
    END IF;

    FOR r IN
        SELECT cod_vino, cantidad
        FROM renglon_transferencia
        WHERE nro = p_nro
        ORDER BY cod_vino
    LOOP
        -- Anexo A.6: bloquear y verificar existencia y suficiencia antes de descontar.
        SELECT cantidad INTO v_stock
        FROM stock_deposito
        WHERE cod_vino = r.cod_vino
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'vino % sin fila en stock_deposito', r.cod_vino;
        END IF;

        IF v_stock < r.cantidad THEN
            RAISE EXCEPTION 'stock insuficiente del vino %: hay % y se piden %',
                r.cod_vino, v_stock, r.cantidad;
        END IF;

        UPDATE stock_deposito
        SET cantidad = cantidad - r.cantidad
        WHERE cod_vino = r.cod_vino;

        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (v_id_sala, r.cod_vino, r.cantidad)
        ON CONFLICT (id_sala, cod_vino)
        DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;
    END LOOP;

    UPDATE transferencia
    SET estado = 'procesado'
    WHERE nro = p_nro;
END;
$$;

COMMIT;
