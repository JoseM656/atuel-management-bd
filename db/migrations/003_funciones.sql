-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/003_funciones.sql
-- Etapa 2: funciones de la capa de datos (PostgreSQL 14+)
--
-- Cuatro funciones PL/pgSQL reutilizadas por triggers (005), procedimientos
-- (004) y consultas (etapa 5). Cada una con cabecera indicando propósito,
-- parámetros y volatilidad. Ninguna es IMMUTABLE: leen tablas o CURRENT_DATE.
--
--   fn_descuento_cliente  -> RN-06 / RI-06
--   fn_stock_sala         -> RN-09 (validación de stock en venta)
--   fn_total_comprobante  -> RN-08
--   fn_antiguedad_anios   -> U2 (+20 % a empleados con >5 años)
--
-- Se aplica después de 001 y 002, sobre la misma base.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- fn_descuento_cliente
-- Propósito: devolver el porcentaje de descuento de un cliente según su
--   tipo (RN-06: socio 10 %, distribuidor 20 %, exportador 30 %) con la
--   excepción RI-06 (exportador con más de 3 permisos -> 35 %).
-- Parámetros: p_id_cliente INTEGER.
-- Retorno: NUMERIC(5,2). Volatilidad: STABLE (lee cliente y permisos).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER)
RETURNS NUMERIC(5,2)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tipo           tipo_cliente;
    v_cant_permisos  INTEGER;
    v_descuento      NUMERIC(5,2);
BEGIN
    SELECT tipo INTO v_tipo
    FROM cliente
    WHERE id_cliente = p_id_cliente;

    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'cliente % no existe', p_id_cliente;
    END IF;

    v_descuento := CASE v_tipo
        WHEN 'socio'        THEN 10.00
        WHEN 'distribuidor' THEN 20.00
        WHEN 'exportador'   THEN 30.00
        ELSE 0.00
    END;

    IF v_tipo = 'exportador' THEN
        SELECT count(*) INTO v_cant_permisos
        FROM permiso_exportacion
        WHERE id_cliente = p_id_cliente;

        IF v_cant_permisos > 3 THEN
            v_descuento := 35.00;  -- RI-06
        END IF;
    END IF;

    RETURN v_descuento;
END;
$$;

-- ---------------------------------------------------------------------
-- fn_stock_sala
-- Propósito: devolver la cantidad en stock de un vino en una sala (RN-09).
--   Devuelve 0 si no existe la fila (cubre el caso límite del Anexo A.6).
-- Parámetros: p_id_sala INTEGER, p_cod_vino INTEGER.
-- Retorno: INTEGER. Volatilidad: STABLE (lee stock_sala).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_sala(p_id_sala INTEGER, p_cod_vino INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_cantidad INTEGER;
BEGIN
    SELECT cantidad INTO v_cantidad
    FROM stock_sala
    WHERE id_sala = p_id_sala AND cod_vino = p_cod_vino;

    RETURN COALESCE(v_cantidad, 0);
END;
$$;

-- ---------------------------------------------------------------------
-- fn_total_comprobante
-- Propósito: calcular el total de un comprobante aplicando el descuento
--   sobre el subtotal (RN-08). El subtotal lo arma el trigger de renglones;
--   esta función solo deriva total = subtotal * (1 - descuento/100).
-- Parámetros: p_nro INTEGER.
-- Retorno: NUMERIC(12,2). Volatilidad: STABLE (lee comprobante).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro INTEGER)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_subtotal   NUMERIC(12,2);
    v_porcentaje NUMERIC(5,2);
BEGIN
    SELECT subtotal, porcentaje_descuento
    INTO v_subtotal, v_porcentaje
    FROM comprobante
    WHERE nro = p_nro;

    IF v_subtotal IS NULL THEN
        RAISE EXCEPTION 'comprobante % no existe', p_nro;
    END IF;

    RETURN ROUND(v_subtotal * (1 - v_porcentaje / 100.0), 2);
END;
$$;

-- ---------------------------------------------------------------------
-- fn_antiguedad_anios
-- Propósito: devolver los años de antigüedad desde una fecha de ingreso
--   hasta hoy. Usada por U2 (empleados con más de 5 años).
-- Parámetros: p_fecha_ingreso DATE.
-- Retorno: INTEGER. Volatilidad: STABLE (usa CURRENT_DATE).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha_ingreso DATE)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha_ingreso))::INTEGER;
END;
$$;

COMMIT;
