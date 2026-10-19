-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/005_triggers.sql
-- Etapa 2: triggers de integridad y lógica (PostgreSQL 14+)
--
-- Cobertura de reglas:
--   RN-05  suma de cortes = 100          (constraint trigger diferido)
--   RN-06  descuento base según tipo     (BEFORE INSERT/UPDATE cliente + comprobante)
--   RN-08  totales y stock en venta      (BEFORE/AFTER INSERT renglon_comprobante)
--   RN-09  no vender sin stock           (BEFORE INSERT renglon_comprobante)
--   RN-10  estados de ingreso sin retroceso
--   RN-11  estados y fecha de transferencia
--   RN-12  renglones bloqueados fuera de confección
--   RN-13  auditoría de precio           (AFTER UPDATE vino)
--   RI-01  encargado en sala de su localidad (constraint triggers diferidos)
--   RI-02  todo vino con >=1 maridaje    (constraint triggers diferidos)
--   RI-03  precio unitario copia de vino.precio (BEFORE INSERT renglon_comprobante)
--   RI-04  vinos del ingreso de su bodega de origen
--   RI-05  transportista cubre la localidad del depósito
--   RI-06  exportador con >3 permisos -> 35 % (fn_descuento_cliente)
--   RI-07  ya cubierta por FK compuesta (id_cliente, tipo) en 001 (sin trigger)
--   Totalidad de la jerarquía cliente -> subtipo (constraint trigger diferido)
--
-- Nota sobre stock en venta: el BEFORE INSERT valida y bloquea la fila de
-- stock (FOR UPDATE) para evitar sobreventa en concurrencia; el AFTER INSERT
-- descuenta y recalcula subtotal/total.
--
-- Se aplica después de 001..004, sobre la misma base.
-- =====================================================================

BEGIN;

-- =====================================================================
-- 1. Venta: renglón de comprobante (RN-08, RN-09, RI-03)
-- =====================================================================

-- ---------------------------------------------------------------------
-- BEFORE INSERT en renglon_comprobante
--   RN-09: valida y bloquea el stock de la sala (FOR UPDATE).
--   RI-03: precio_unitario = copia histórica de vino.precio.
--   RN-08: importe_descuento y subtotal del renglón (la API no los envía).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_renglon_comprobante_bi() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sala    INTEGER;
    v_porcentaje NUMERIC(5,2);
    v_precio     NUMERIC(12,2);
    v_stock      INTEGER;
BEGIN
    SELECT c.id_sala, c.porcentaje_descuento INTO v_id_sala, v_porcentaje
    FROM comprobante c
    WHERE c.nro = NEW.nro;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'comprobante % no existe', NEW.nro;
    END IF;

    -- RN-09: bloquear la fila de stock para evitar sobreventa concurrente.
    PERFORM 1
    FROM stock_sala
    WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino
    FOR UPDATE;

    v_stock := fn_stock_sala(v_id_sala, NEW.cod_vino);
    IF v_stock < NEW.cantidad THEN
        RAISE EXCEPTION 'stock insuficiente del vino % en la sala %: hay % y se piden %',
            NEW.cod_vino, v_id_sala, v_stock, NEW.cantidad;
    END IF;

    -- RI-03: precio unitario como copia histórica del precio actual.
    SELECT precio INTO v_precio FROM vino WHERE cod_vino = NEW.cod_vino;
    NEW.precio_unitario := v_precio;

    -- RN-08: importe y subtotal del renglón.
    NEW.importe_descuento := ROUND(NEW.cantidad * v_precio * (v_porcentaje / 100.0), 2);
    NEW.subtotal := ROUND(NEW.cantidad * v_precio - NEW.importe_descuento, 2);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_comprobante_bi
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_fn_renglon_comprobante_bi();

-- ---------------------------------------------------------------------
-- AFTER INSERT en renglon_comprobante
--   RN-09: descuenta el stock de la sala.
--   RN-08: recalcula comprobante.subtotal (suma sin descuento) y total.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_renglon_comprobante_ai() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sala INTEGER;
BEGIN
    SELECT id_sala INTO v_id_sala FROM comprobante WHERE nro = NEW.nro;

    UPDATE stock_sala
    SET cantidad = cantidad - NEW.cantidad
    WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino;

    UPDATE comprobante
    SET subtotal = (
        SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
        FROM renglon_comprobante
        WHERE nro = NEW.nro
    )
    WHERE nro = NEW.nro;

    UPDATE comprobante
    SET total = fn_total_comprobante(NEW.nro)
    WHERE nro = NEW.nro;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_comprobante_ai
AFTER INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_fn_renglon_comprobante_ai();

-- =====================================================================
-- 2. Descuento de cliente y comprobante (RN-06)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Descuento base según tipo (RN-06). El 35 % de RI-06 lo aplica el trigger
-- de permiso_exportacion. Se dispara solo al insertar o cambiar el tipo,
-- así el UPDATE de descuento desde permisos no provoca recursión.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_cliente_descuento() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.descuento := CASE NEW.tipo
        WHEN 'socio'        THEN 10.00
        WHEN 'distribuidor' THEN 20.00
        WHEN 'exportador'   THEN 30.00
        ELSE NEW.descuento
    END;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cliente_descuento
BEFORE INSERT OR UPDATE OF tipo ON cliente
FOR EACH ROW EXECUTE FUNCTION trg_fn_cliente_descuento();

-- ---------------------------------------------------------------------
-- Copia histórica del descuento en el comprobante (RN-08). Se calcula con
-- fn_descuento_cliente para incluir el 35 % de RI-06 si corresponde.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_comprobante_descuento() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.porcentaje_descuento := fn_descuento_cliente(NEW.id_cliente);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_descuento
BEFORE INSERT ON comprobante
FOR EACH ROW EXECUTE FUNCTION trg_fn_comprobante_descuento();

-- ---------------------------------------------------------------------
-- BEFORE UPDATE en comprobante (RN-08): subtotal y total no se cargan a
-- mano. Se recalculan siempre desde los renglones; si la sentencia intenta
-- escribir un valor distinto del calculado, se rechaza. Cambiar
-- porcentaje_descuento (U1) recalcula el total automáticamente.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_comprobante_importes() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_subtotal NUMERIC(12,2);
    v_total    NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0) INTO v_subtotal
    FROM renglon_comprobante
    WHERE nro = NEW.nro;

    v_total := ROUND(v_subtotal * (1 - NEW.porcentaje_descuento / 100.0), 2);

    IF NEW.subtotal IS DISTINCT FROM OLD.subtotal AND NEW.subtotal <> v_subtotal THEN
        RAISE EXCEPTION 'el subtotal del comprobante % no se carga a mano: según sus renglones es % (RN-08)',
            NEW.nro, v_subtotal;
    END IF;

    IF NEW.total IS DISTINCT FROM OLD.total AND NEW.total <> v_total THEN
        RAISE EXCEPTION 'el total del comprobante % no se carga a mano: según sus renglones es % (RN-08)',
            NEW.nro, v_total;
    END IF;

    NEW.subtotal := v_subtotal;
    NEW.total := v_total;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_importes
BEFORE UPDATE ON comprobante
FOR EACH ROW EXECUTE FUNCTION trg_fn_comprobante_importes();

-- =====================================================================
-- 3. Estados de documentos (RN-10, RN-11) y fecha de confección (RN-11)
-- =====================================================================

-- Transiciones válidas: en_confeccion -> terminado -> procesado, sin retroceso.
CREATE OR REPLACE FUNCTION trg_fn_estado_avance() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
       OR (OLD.estado = 'terminado' AND NEW.estado = 'procesado') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'transición de estado inválida: % -> %', OLD.estado, NEW.estado;
END;
$$;

CREATE TRIGGER trg_ingreso_estado
BEFORE UPDATE ON ingreso
FOR EACH ROW EXECUTE FUNCTION trg_fn_estado_avance();

CREATE TRIGGER trg_transferencia_estado
BEFORE UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_fn_estado_avance();

-- Fecha de confección: se fuerza la actual al insertar y no se puede modificar (RN-11).
CREATE OR REPLACE FUNCTION trg_fn_fecha_confeccion() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF TG_OP = 'UPDATE' AND NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION 'fecha_confeccion no puede modificarse';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_fn_fecha_confeccion();

-- =====================================================================
-- 4. Bloqueo de renglones fuera de confección (RN-12)
-- =====================================================================

CREATE OR REPLACE FUNCTION trg_fn_renglon_ingreso_doc() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cod_ingreso INTEGER;
    v_estado      estado_documento;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_cod_ingreso := OLD.cod_ingreso;
    ELSE
        v_cod_ingreso := NEW.cod_ingreso;
    END IF;

    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = v_cod_ingreso;

    -- Borrado en cascada desde la cabecera: el ingreso ya no existe y se
    -- borra entero (por ejemplo D5), no se está editando un renglón suelto.
    IF TG_OP = 'DELETE' AND NOT FOUND THEN
        RETURN OLD;
    END IF;

    IF v_estado IS DISTINCT FROM 'en_confeccion' THEN
        RAISE EXCEPTION 'el ingreso % no está en confección, no se pueden modificar sus renglones',
            v_cod_ingreso;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_doc
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION trg_fn_renglon_ingreso_doc();

CREATE OR REPLACE FUNCTION trg_fn_renglon_transferencia_doc() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_nro    INTEGER;
    v_estado estado_documento;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_nro := OLD.nro;
    ELSE
        v_nro := NEW.nro;
    END IF;

    SELECT estado INTO v_estado FROM transferencia WHERE nro = v_nro;

    -- Borrado en cascada desde la cabecera (ver trg_fn_renglon_ingreso_doc).
    IF TG_OP = 'DELETE' AND NOT FOUND THEN
        RETURN OLD;
    END IF;

    IF v_estado IS DISTINCT FROM 'en_confeccion' THEN
        RAISE EXCEPTION 'la transferencia % no está en confección, no se pueden modificar sus renglones',
            v_nro;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_transferencia_doc
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION trg_fn_renglon_transferencia_doc();

-- =====================================================================
-- 5. Auditoría de precio (RN-13)
-- =====================================================================

CREATE OR REPLACE FUNCTION trg_fn_auditoria_precio() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.precio IS DISTINCT FROM OLD.precio THEN
        INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo)
        VALUES (OLD.cod_vino, OLD.precio, NEW.precio);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vino_auditoria_precio
AFTER UPDATE ON vino
FOR EACH ROW EXECUTE FUNCTION trg_fn_auditoria_precio();

-- =====================================================================
-- 6. Reglas implícitas RI-04 y RI-05
-- =====================================================================

-- RI-04: los vinos de un ingreso son de la bodega de origen.
CREATE OR REPLACE FUNCTION trg_fn_renglon_ingreso_bodega() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuit_bodega cuit;
BEGIN
    SELECT cuit_bodega INTO v_cuit_bodega FROM ingreso WHERE cod_ingreso = NEW.cod_ingreso;

    IF NOT EXISTS (
        SELECT 1 FROM vino
        WHERE cod_vino = NEW.cod_vino AND cuit_bodega = v_cuit_bodega
    ) THEN
        RAISE EXCEPTION 'el vino % no pertenece a la bodega de origen del ingreso', NEW.cod_vino;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_bodega
BEFORE INSERT OR UPDATE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION trg_fn_renglon_ingreso_bodega();

-- RI-05: el transportista cubre la localidad del depósito.
CREATE OR REPLACE FUNCTION trg_fn_ingreso_transportista() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_localidad INTEGER;
BEGIN
    SELECT id_localidad INTO v_id_localidad FROM deposito WHERE id = 1;

    IF NOT EXISTS (
        SELECT 1 FROM transportista_localidad
        WHERE cod_transportista = NEW.cod_transportista AND id_localidad = v_id_localidad
    ) THEN
        RAISE EXCEPTION 'el transportista % no cubre la localidad del depósito', NEW.cod_transportista;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_transportista
BEFORE INSERT OR UPDATE OF cod_transportista ON ingreso
FOR EACH ROW EXECUTE FUNCTION trg_fn_ingreso_transportista();

-- =====================================================================
-- 7. RI-06: exportador con >3 permisos -> 35 % (recalcula con fn_descuento_cliente)
-- =====================================================================

CREATE OR REPLACE FUNCTION trg_fn_permiso_descuento() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE cliente SET descuento = fn_descuento_cliente(OLD.id_cliente)
        WHERE id_cliente = OLD.id_cliente;
        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.id_cliente IS DISTINCT FROM NEW.id_cliente THEN
        UPDATE cliente SET descuento = fn_descuento_cliente(OLD.id_cliente)
        WHERE id_cliente = OLD.id_cliente;
    END IF;

    UPDATE cliente SET descuento = fn_descuento_cliente(NEW.id_cliente)
    WHERE id_cliente = NEW.id_cliente;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_permiso_descuento
AFTER INSERT OR UPDATE OR DELETE ON permiso_exportacion
FOR EACH ROW EXECUTE FUNCTION trg_fn_permiso_descuento();

-- =====================================================================
-- 8. Constraint triggers diferidos (RN-05, RI-02, RI-01, totalidad)
--    Se evalúan al COMMIT, cuando la transacción ya cargó todo el ciclo.
-- =====================================================================

-- RN-05: la suma de porcentajes de corte de cada vino es 100.
CREATE OR REPLACE FUNCTION trg_fn_suma_cortes() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT cod_vino FROM composicion GROUP BY cod_vino
        HAVING SUM(porcentaje) <> 100
    ) THEN
        RAISE EXCEPTION 'la composición de un vino no suma 100';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_composicion_suma_100
AFTER INSERT OR UPDATE OR DELETE ON composicion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_fn_suma_cortes();

-- RI-02: todo vino tiene al menos un maridaje.
CREATE OR REPLACE FUNCTION trg_fn_vino_maridaje() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM vino v
        WHERE NOT EXISTS (SELECT 1 FROM vino_maridaje vm WHERE vm.cod_vino = v.cod_vino)
    ) THEN
        RAISE EXCEPTION 'todo vino debe tener al menos un maridaje';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_vino_maridaje_obligatorio
AFTER INSERT OR UPDATE ON vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_fn_vino_maridaje();

CREATE CONSTRAINT TRIGGER trg_vino_maridaje_borrado
AFTER INSERT OR UPDATE OR DELETE ON vino_maridaje
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_fn_vino_maridaje();

-- RI-01: el encargado trabaja en una sala de su misma localidad.
CREATE OR REPLACE FUNCTION trg_fn_encargado() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM localidad l
        JOIN empleado e ON e.cuit = l.cuit_encargado
        JOIN sala_venta s ON s.id_sala = e.id_sala
        WHERE s.id_localidad <> l.id_localidad
    ) THEN
        RAISE EXCEPTION 'el encargado debe trabajar en una sala de su localidad';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_encargado_localidad
AFTER INSERT OR UPDATE ON localidad
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_fn_encargado();

CREATE CONSTRAINT TRIGGER trg_encargado_empleado
AFTER INSERT OR UPDATE ON empleado
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_fn_encargado();

CREATE CONSTRAINT TRIGGER trg_encargado_sala
AFTER INSERT OR UPDATE ON sala_venta
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_fn_encargado();

-- Totalidad de la jerarquía: todo cliente tiene fila en su subtipo.
CREATE OR REPLACE FUNCTION trg_fn_cliente_subtipo() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM cliente c
        WHERE NOT (
            (c.tipo = 'socio'        AND EXISTS (SELECT 1 FROM socio s        WHERE s.id_cliente = c.id_cliente))
            OR (c.tipo = 'distribuidor' AND EXISTS (SELECT 1 FROM distribuidor d WHERE d.id_cliente = c.id_cliente))
            OR (c.tipo = 'exportador'   AND EXISTS (SELECT 1 FROM exportador e   WHERE e.id_cliente = c.id_cliente))
        )
    ) THEN
        RAISE EXCEPTION 'todo cliente debe tener su fila en el subtipo correspondiente';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_cliente_subtipo
AFTER INSERT OR UPDATE ON cliente
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_fn_cliente_subtipo();

COMMIT;
