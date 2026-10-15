-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/002_constraints.sql
-- Etapa 2: restricciones de integridad adicionales (PostgreSQL 14+)
--
-- Contenido: UNIQUE, CHECK y DEFAULT que completan el DDL base de
-- 001_esquema.sql (que ya crea tipos, tablas, PK y FK). El contenido se
-- deriva del diccionario de datos (docs/entregables/etapa 1/diccionario_datos.md).
--
-- Mecanismos cubiertos: RN-01 (precio único > 0), RN-04 (índice único de
-- expresión parcela/campaña), RN-06 (rango de descuento), RN-07 (vencimiento
-- > emisión), RN-09 (stock >= 0), RN-15 (graduación 5-20 y positivos).
--
-- Se aplica después de 001, sobre la misma base, en una transacción.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Ubicación y personal
-- ---------------------------------------------------------------------

ALTER TABLE departamento
    ADD CONSTRAINT uq_departamento_nombre_provincia UNIQUE (nombre, provincia);

ALTER TABLE localidad
    ADD CONSTRAINT uq_localidad_encargado UNIQUE (cuit_encargado);

ALTER TABLE deposito
    ALTER COLUMN id SET DEFAULT 1,
    ADD CONSTRAINT ck_deposito_id CHECK (id = 1),
    ADD CONSTRAINT uq_deposito_localidad UNIQUE (id_localidad);

ALTER TABLE sala_venta
    ADD CONSTRAINT ck_sala_numero CHECK (numero > 0);

ALTER TABLE empleado
    ADD CONSTRAINT ck_empleado_salario CHECK (salario > 0);

-- ---------------------------------------------------------------------
-- 2. Producción
-- ---------------------------------------------------------------------

ALTER TABLE finca
    ADD CONSTRAINT ck_finca_superficie CHECK (superficie_ha > 0);

ALTER TABLE parcela
    ADD CONSTRAINT ck_parcela_nro CHECK (nro_parcela > 0),
    ADD CONSTRAINT ck_parcela_superficie CHECK (superficie_ha > 0),
    ADD CONSTRAINT ck_parcela_anio CHECK (anio_plantacion BETWEEN 1900 AND 2100);

ALTER TABLE cepa
    ADD CONSTRAINT uq_cepa_nombre UNIQUE (nombre);

ALTER TABLE lote_uva
    ADD CONSTRAINT ck_lote_kg CHECK (kg > 0);

-- RN-04: una cosecha por parcela y campaña (campaña = año de fecha_cosecha).
-- Índice único de expresión, no puede ser una UNIQUE de columna.
CREATE UNIQUE INDEX idx_lote_uva_parcela_campana
    ON lote_uva (id_finca, nro_parcela, (EXTRACT(YEAR FROM fecha_cosecha)));

ALTER TABLE analisis_calidad
    ADD CONSTRAINT ck_analisis_brix CHECK (brix BETWEEN 0 AND 40),
    ADD CONSTRAINT ck_analisis_ph CHECK (ph > 0 AND ph < 14),
    ADD CONSTRAINT ck_analisis_acidez CHECK (acidez_total > 0);

-- ---------------------------------------------------------------------
-- 3. Bodegas y vinos
-- ---------------------------------------------------------------------

ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_volumen UNIQUE (nombre, anada, volumen_ml),
    ADD CONSTRAINT ck_vino_anada CHECK (anada BETWEEN 1990 AND 2100),
    ADD CONSTRAINT ck_vino_volumen CHECK (volumen_ml IN (187, 375, 750, 1500, 3000)),
    ADD CONSTRAINT ck_vino_graduacion CHECK (graduacion BETWEEN 5 AND 20),  -- RN-15
    ADD CONSTRAINT ck_vino_precio CHECK (precio > 0);                        -- RN-01

ALTER TABLE composicion
    ADD CONSTRAINT ck_composicion_porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100);

ALTER TABLE maridaje
    ADD CONSTRAINT uq_maridaje_nombre UNIQUE (nombre),
    ADD CONSTRAINT ck_maridaje_temperatura CHECK (temperatura_servicio BETWEEN 0 AND 25);

ALTER TABLE auditoria_precio
    ALTER COLUMN fecha_hora SET DEFAULT now(),
    ALTER COLUMN usuario SET DEFAULT current_user;

-- ---------------------------------------------------------------------
-- 4. Clientes y ventas
-- ---------------------------------------------------------------------

ALTER TABLE cliente
    ADD CONSTRAINT uq_cliente_tipo_nro_doc UNIQUE (tipo_doc, nro_doc),
    ADD CONSTRAINT ck_cliente_descuento CHECK (descuento BETWEEN 0 AND 35),  -- RN-06
    ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

-- Disjunción de la jerarquía: cada subtipo fija su tipo por CHECK + DEFAULT.
ALTER TABLE socio
    ALTER COLUMN tipo SET DEFAULT 'socio',
    ADD CONSTRAINT ck_socio_tipo CHECK (tipo = 'socio');

ALTER TABLE distribuidor
    ALTER COLUMN tipo SET DEFAULT 'distribuidor',
    ADD CONSTRAINT ck_distribuidor_tipo CHECK (tipo = 'distribuidor'),
    ADD CONSTRAINT uq_distribuidor_habilitacion UNIQUE (nro_habilitacion);

ALTER TABLE exportador
    ALTER COLUMN tipo SET DEFAULT 'exportador',
    ADD CONSTRAINT ck_exportador_tipo CHECK (tipo = 'exportador');

-- RN-07: el vencimiento es posterior a la emisión (CHECK entre columnas)
ALTER TABLE permiso_exportacion
    ADD CONSTRAINT ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision);

ALTER TABLE comprobante
    ALTER COLUMN fecha SET DEFAULT CURRENT_DATE,
    ALTER COLUMN subtotal SET DEFAULT 0,
    ALTER COLUMN total SET DEFAULT 0,
    ADD CONSTRAINT ck_comprobante_subtotal CHECK (subtotal >= 0),
    ADD CONSTRAINT ck_comprobante_descuento CHECK (porcentaje_descuento BETWEEN 0 AND 35),
    ADD CONSTRAINT ck_comprobante_total CHECK (total >= 0);

ALTER TABLE renglon_comprobante
    ADD CONSTRAINT ck_rc_cantidad CHECK (cantidad > 0),
    ADD CONSTRAINT ck_rc_precio_unitario CHECK (precio_unitario > 0),
    ADD CONSTRAINT ck_rc_importe_descuento CHECK (importe_descuento >= 0),
    ADD CONSTRAINT ck_rc_subtotal CHECK (subtotal >= 0);

-- ---------------------------------------------------------------------
-- 5. Logística y stock
-- ---------------------------------------------------------------------

ALTER TABLE transportista
    ADD CONSTRAINT uq_transportista_cuit UNIQUE (cuit),
    ADD CONSTRAINT ck_transportista_email CHECK (email LIKE '%_@_%');

ALTER TABLE ingreso
    ALTER COLUMN fecha SET DEFAULT CURRENT_DATE,
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE renglon_ingreso
    ADD CONSTRAINT ck_ri_cantidad CHECK (cantidad > 0);

ALTER TABLE transferencia
    ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE,
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT ck_rt_cantidad CHECK (cantidad > 0);

-- RN-09: el stock nunca es negativo
ALTER TABLE stock_sala
    ALTER COLUMN cantidad SET DEFAULT 0,
    ADD CONSTRAINT ck_stock_sala_cantidad CHECK (cantidad >= 0);

ALTER TABLE stock_deposito
    ALTER COLUMN cantidad SET DEFAULT 0,
    ADD CONSTRAINT ck_stock_deposito_cantidad CHECK (cantidad >= 0);

COMMIT;
