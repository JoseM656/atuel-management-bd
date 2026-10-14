-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/migrations/001_esquema.sql
-- Etapa 1: esquema físico base (PostgreSQL 14+)
--
-- Contenido: tipos enumerados, dominio, tablas, columnas con NOT NULL,
-- claves primarias y claves foráneas (con sus acciones referenciales).
-- Las restricciones UNIQUE, CHECK y DEFAULT adicionales se agregan en
-- 002_constraints.sql (etapa 2). Las únicas UNIQUE incluidas acá son las
-- que una FK necesita para existir (cliente(id_cliente, tipo)).
--
-- Orden de creación: cada tabla se crea después de las tablas a las que
-- referencia. El ciclo localidad -> empleado -> sala_venta -> localidad
-- se resuelve agregando la FK del encargado al final, como DEFERRABLE.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Tipos propios
-- ---------------------------------------------------------------------

CREATE TYPE estado_documento AS ENUM ('en_confeccion', 'terminado', 'procesado');
CREATE TYPE tipo_cliente     AS ENUM ('socio', 'distribuidor', 'exportador');
CREATE TYPE tipo_vino        AS ENUM ('tinto', 'blanco', 'rosado', 'espumante');
CREATE TYPE tipo_cepa        AS ENUM ('tinta', 'blanca');
CREATE TYPE dia_semana       AS ENUM ('lunes', 'martes', 'miercoles', 'jueves',
                                      'viernes', 'sabado', 'domingo');

-- CUIT: 11 dígitos, sin guiones
CREATE DOMAIN cuit AS CHAR(11)
    CHECK (VALUE ~ '^[0-9]{11}$');

-- ---------------------------------------------------------------------
-- 2. Ubicación y personal
-- ---------------------------------------------------------------------

CREATE TABLE departamento (
    id_departamento  INTEGER      GENERATED ALWAYS AS IDENTITY,
    nombre           VARCHAR(60)  NOT NULL,
    provincia        VARCHAR(40)  NOT NULL,
    CONSTRAINT pk_departamento PRIMARY KEY (id_departamento)
);

-- La FK de cuit_encargado se agrega después de crear empleado (ver ALTER al final de la sección)
CREATE TABLE localidad (
    id_localidad     INTEGER      GENERATED ALWAYS AS IDENTITY,
    nombre           VARCHAR(80)  NOT NULL,
    provincia        VARCHAR(40)  NOT NULL,
    codigo_postal    VARCHAR(8)   NOT NULL,
    cuit_encargado   cuit         NOT NULL,
    CONSTRAINT pk_localidad PRIMARY KEY (id_localidad)
);

-- Depósito central único (CHECK id = 1 en 002)
CREATE TABLE deposito (
    id               SMALLINT     NOT NULL,
    id_localidad     INTEGER      NOT NULL,
    CONSTRAINT pk_deposito PRIMARY KEY (id),
    CONSTRAINT fk_deposito_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT
);

CREATE TABLE sala_venta (
    id_sala          INTEGER      GENERATED ALWAYS AS IDENTITY,
    calle            VARCHAR(80)  NOT NULL,
    numero           INTEGER      NOT NULL,
    dia_cierre       dia_semana   NOT NULL,
    id_localidad     INTEGER      NOT NULL,
    CONSTRAINT pk_sala_venta PRIMARY KEY (id_sala),
    CONSTRAINT fk_sala_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT
);

CREATE TABLE empleado (
    cuit             cuit           NOT NULL,
    nombre           VARCHAR(100)   NOT NULL,
    fecha_ingreso    DATE           NOT NULL,
    salario          NUMERIC(12,2)  NOT NULL,
    id_sala          INTEGER        NOT NULL,                    -- RN-03
    CONSTRAINT pk_empleado PRIMARY KEY (cuit),
    CONSTRAINT fk_empleado_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT
);

-- Encargado regional (RN-02). Diferible para poder cargar localidad,
-- sala y empleado en la misma transacción.
ALTER TABLE localidad
    ADD CONSTRAINT fk_localidad_encargado FOREIGN KEY (cuit_encargado)
        REFERENCES empleado (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

-- ---------------------------------------------------------------------
-- 3. Producción
-- ---------------------------------------------------------------------

CREATE TABLE cepa (
    id_cepa          INTEGER      GENERATED ALWAYS AS IDENTITY,
    nombre           VARCHAR(40)  NOT NULL,
    tipo             tipo_cepa    NOT NULL,
    CONSTRAINT pk_cepa PRIMARY KEY (id_cepa)
);

CREATE TABLE finca (
    id_finca         INTEGER        GENERATED ALWAYS AS IDENTITY,
    nombre           VARCHAR(80)    NOT NULL,
    superficie_ha    NUMERIC(10,2)  NOT NULL,
    id_departamento  INTEGER        NOT NULL,
    CONSTRAINT pk_finca PRIMARY KEY (id_finca),
    CONSTRAINT fk_finca_departamento FOREIGN KEY (id_departamento)
        REFERENCES departamento (id_departamento) ON DELETE RESTRICT
);

-- Entidad débil: clave (finca, n.° de parcela)
CREATE TABLE parcela (
    id_finca         INTEGER        NOT NULL,
    nro_parcela      SMALLINT       NOT NULL,
    superficie_ha    NUMERIC(10,2)  NOT NULL,
    anio_plantacion  SMALLINT       NOT NULL,
    id_cepa          INTEGER        NOT NULL,                    -- RN-04: una sola cepa
    CONSTRAINT pk_parcela PRIMARY KEY (id_finca, nro_parcela),
    CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
        REFERENCES finca (id_finca) ON DELETE CASCADE,
    CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT
);

CREATE TABLE bodega (
    cuit             cuit          NOT NULL,
    razon_social     VARCHAR(120)  NOT NULL,
    domicilio        VARCHAR(150)  NOT NULL,
    CONSTRAINT pk_bodega PRIMARY KEY (cuit)
);

-- La campaña no se guarda: es el año de fecha_cosecha.
-- La unicidad (parcela, campaña) se crea en 002 como índice único de expresión.
CREATE TABLE lote_uva (
    nro_lote         INTEGER        GENERATED ALWAYS AS IDENTITY,
    id_finca         INTEGER        NOT NULL,
    nro_parcela      SMALLINT       NOT NULL,
    fecha_cosecha    DATE           NOT NULL,
    kg               NUMERIC(10,2)  NOT NULL,
    cuit_bodega      cuit           NOT NULL,
    CONSTRAINT pk_lote_uva PRIMARY KEY (nro_lote),
    CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, nro_parcela)
        REFERENCES parcela (id_finca, nro_parcela) ON DELETE RESTRICT,
    CONSTRAINT fk_lote_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE analisis_calidad (
    id_analisis      INTEGER       GENERATED ALWAYS AS IDENTITY,
    nro_lote         INTEGER       NOT NULL,
    fecha            DATE          NOT NULL,
    brix             NUMERIC(4,1)  NOT NULL,
    ph               NUMERIC(3,2)  NOT NULL,
    acidez_total     NUMERIC(5,2)  NOT NULL,                     -- g/L
    CONSTRAINT pk_analisis_calidad PRIMARY KEY (id_analisis),
    CONSTRAINT fk_analisis_lote FOREIGN KEY (nro_lote)
        REFERENCES lote_uva (nro_lote) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 4. Bodegas y vinos
-- ---------------------------------------------------------------------

CREATE TABLE vino (
    cod_vino         INTEGER        GENERATED ALWAYS AS IDENTITY,
    nombre           VARCHAR(80)    NOT NULL,
    tipo             tipo_vino      NOT NULL,
    anada            SMALLINT       NOT NULL,
    volumen_ml       INTEGER        NOT NULL,
    graduacion       NUMERIC(4,2)   NOT NULL,
    precio           NUMERIC(12,2)  NOT NULL,                    -- RN-01: único para toda la red
    cuit_bodega      cuit           NOT NULL,
    CONSTRAINT pk_vino PRIMARY KEY (cod_vino),
    CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- N:M vino-cepa con atributo (la suma de porcentajes = 100 la controla un trigger diferido, RN-05)
CREATE TABLE composicion (
    cod_vino         INTEGER       NOT NULL,
    id_cepa          INTEGER       NOT NULL,
    porcentaje       NUMERIC(5,2)  NOT NULL,
    CONSTRAINT pk_composicion PRIMARY KEY (cod_vino, id_cepa),
    CONSTRAINT fk_composicion_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE,
    CONSTRAINT fk_composicion_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT
);

CREATE TABLE maridaje (
    id_maridaje           INTEGER       GENERATED ALWAYS AS IDENTITY,
    nombre                VARCHAR(60)   NOT NULL,
    temperatura_servicio  NUMERIC(4,1)  NOT NULL,                -- °C
    CONSTRAINT pk_maridaje PRIMARY KEY (id_maridaje)
);

CREATE TABLE vino_maridaje (
    cod_vino         INTEGER  NOT NULL,
    id_maridaje      INTEGER  NOT NULL,
    CONSTRAINT pk_vino_maridaje PRIMARY KEY (cod_vino, id_maridaje),
    CONSTRAINT fk_vm_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE,
    CONSTRAINT fk_vm_maridaje FOREIGN KEY (id_maridaje)
        REFERENCES maridaje (id_maridaje) ON DELETE RESTRICT
);

-- La completa un trigger AFTER UPDATE en vino (RN-13)
CREATE TABLE auditoria_precio (
    id_auditoria     BIGINT         GENERATED ALWAYS AS IDENTITY,
    cod_vino         INTEGER        NOT NULL,
    precio_anterior  NUMERIC(12,2)  NOT NULL,
    precio_nuevo     NUMERIC(12,2)  NOT NULL,
    fecha_hora       TIMESTAMPTZ    NOT NULL,
    usuario          VARCHAR(63)    NOT NULL,
    CONSTRAINT pk_auditoria_precio PRIMARY KEY (id_auditoria),
    CONSTRAINT fk_auditoria_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 5. Clientes y ventas
-- Jerarquía: supertipo + una tabla por subtipo. Cada subtipo referencia
-- cliente(id_cliente, tipo), lo que garantiza la disjunción.
-- ---------------------------------------------------------------------

CREATE TABLE cliente (
    id_cliente           INTEGER       GENERATED ALWAYS AS IDENTITY,
    nombre_razon_social  VARCHAR(120)  NOT NULL,
    tipo_doc             VARCHAR(10)   NOT NULL,
    nro_doc              VARCHAR(15)   NOT NULL,
    direccion            VARCHAR(150)  NOT NULL,
    id_localidad         INTEGER       NOT NULL,
    fecha_alta           DATE          NOT NULL,
    tipo                 tipo_cliente  NOT NULL,
    descuento            NUMERIC(5,2)  NOT NULL,                 -- RN-06, lo mantiene fn_descuento_cliente
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT uq_cliente_id_tipo UNIQUE (id_cliente, tipo),     -- requerida por las FK de los subtipos
    CONSTRAINT fk_cliente_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT
);

CREATE TABLE socio (
    id_cliente       INTEGER       NOT NULL,
    tipo             tipo_cliente  NOT NULL,
    CONSTRAINT pk_socio PRIMARY KEY (id_cliente),
    CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE
);

CREATE TABLE distribuidor (
    id_cliente        INTEGER       NOT NULL,
    tipo              tipo_cliente  NOT NULL,
    zona_cobertura    VARCHAR(100)  NOT NULL,
    nro_habilitacion  VARCHAR(30)   NOT NULL,
    CONSTRAINT pk_distribuidor PRIMARY KEY (id_cliente),
    CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE
);

CREATE TABLE exportador (
    id_cliente       INTEGER       NOT NULL,
    tipo             tipo_cliente  NOT NULL,
    pais_destino     VARCHAR(60)   NOT NULL,
    CONSTRAINT pk_exportador PRIMARY KEY (id_cliente),
    CONSTRAINT fk_exportador_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE
);

-- RN-07: varios permisos por exportador (vencimiento > emisión en 002)
CREATE TABLE permiso_exportacion (
    codigo             VARCHAR(30)  NOT NULL,
    id_cliente         INTEGER      NOT NULL,
    fecha_emision      DATE         NOT NULL,
    fecha_vencimiento  DATE         NOT NULL,
    CONSTRAINT pk_permiso_exportacion PRIMARY KEY (codigo),
    CONSTRAINT fk_permiso_exportador FOREIGN KEY (id_cliente)
        REFERENCES exportador (id_cliente) ON DELETE CASCADE
);

-- subtotal y total los calcula la base (RN-08); porcentaje_descuento es copia histórica
CREATE TABLE comprobante (
    nro                   INTEGER        GENERATED ALWAYS AS IDENTITY,
    fecha                 DATE           NOT NULL,
    id_cliente            INTEGER        NOT NULL,
    id_sala               INTEGER        NOT NULL,
    subtotal              NUMERIC(12,2)  NOT NULL,
    porcentaje_descuento  NUMERIC(5,2)   NOT NULL,
    total                 NUMERIC(12,2)  NOT NULL,
    CONSTRAINT pk_comprobante PRIMARY KEY (nro),
    CONSTRAINT fk_comprobante_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT,
    CONSTRAINT fk_comprobante_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT
);

-- precio_unitario: copia del precio del vino al vender (la completa un trigger)
CREATE TABLE renglon_comprobante (
    nro                INTEGER        NOT NULL,
    cod_vino           INTEGER        NOT NULL,
    cantidad           INTEGER        NOT NULL,
    precio_unitario    NUMERIC(12,2)  NOT NULL,
    importe_descuento  NUMERIC(12,2)  NOT NULL,
    subtotal           NUMERIC(12,2)  NOT NULL,
    CONSTRAINT pk_renglon_comprobante PRIMARY KEY (nro, cod_vino),
    CONSTRAINT fk_rc_comprobante FOREIGN KEY (nro)
        REFERENCES comprobante (nro) ON DELETE CASCADE,
    CONSTRAINT fk_rc_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 6. Logística y stock
-- ---------------------------------------------------------------------

CREATE TABLE transportista (
    cod_transportista  INTEGER       GENERATED ALWAYS AS IDENTITY,
    razon_social       VARCHAR(120)  NOT NULL,
    cuit               cuit          NOT NULL,
    email              VARCHAR(120)  NOT NULL,
    telefono           VARCHAR(30)   NOT NULL,
    domicilio          VARCHAR(150)  NOT NULL,
    CONSTRAINT pk_transportista PRIMARY KEY (cod_transportista)
);

CREATE TABLE transportista_localidad (
    cod_transportista  INTEGER  NOT NULL,
    id_localidad       INTEGER  NOT NULL,
    CONSTRAINT pk_transportista_localidad PRIMARY KEY (cod_transportista, id_localidad),
    CONSTRAINT fk_tl_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista) ON DELETE CASCADE,
    CONSTRAINT fk_tl_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT
);

CREATE TABLE ingreso (
    cod_ingreso        INTEGER           GENERATED ALWAYS AS IDENTITY,
    fecha              DATE              NOT NULL,
    estado             estado_documento  NOT NULL,               -- RN-10
    cod_transportista  INTEGER           NOT NULL,
    cuit_bodega        cuit              NOT NULL,
    CONSTRAINT pk_ingreso PRIMARY KEY (cod_ingreso),
    CONSTRAINT fk_ingreso_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista) ON DELETE RESTRICT,
    CONSTRAINT fk_ingreso_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE renglon_ingreso (
    cod_ingreso      INTEGER  NOT NULL,
    cod_vino         INTEGER  NOT NULL,
    cantidad         INTEGER  NOT NULL,
    CONSTRAINT pk_renglon_ingreso PRIMARY KEY (cod_ingreso, cod_vino),
    CONSTRAINT fk_ri_ingreso FOREIGN KEY (cod_ingreso)
        REFERENCES ingreso (cod_ingreso) ON DELETE CASCADE,
    CONSTRAINT fk_ri_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT
);

CREATE TABLE transferencia (
    nro               INTEGER           GENERATED ALWAYS AS IDENTITY,
    id_sala           INTEGER           NOT NULL,
    fecha_confeccion  DATE              NOT NULL,                -- RN-11: fecha actual, no modificable
    estado            estado_documento  NOT NULL,                -- RN-11
    CONSTRAINT pk_transferencia PRIMARY KEY (nro),
    CONSTRAINT fk_transferencia_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT
);

CREATE TABLE renglon_transferencia (
    nro              INTEGER  NOT NULL,
    cod_vino         INTEGER  NOT NULL,
    cantidad         INTEGER  NOT NULL,
    CONSTRAINT pk_renglon_transferencia PRIMARY KEY (nro, cod_vino),
    CONSTRAINT fk_rt_transferencia FOREIGN KEY (nro)
        REFERENCES transferencia (nro) ON DELETE CASCADE,
    CONSTRAINT fk_rt_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT
);

CREATE TABLE stock_sala (
    id_sala          INTEGER  NOT NULL,
    cod_vino         INTEGER  NOT NULL,
    cantidad         INTEGER  NOT NULL,                          -- RN-09 (CHECK >= 0 en 002)
    CONSTRAINT pk_stock_sala PRIMARY KEY (id_sala, cod_vino),
    CONSTRAINT fk_ss_sala FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT,
    CONSTRAINT fk_ss_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT
);

-- Un solo depósito central: no lleva columna de depósito
CREATE TABLE stock_deposito (
    cod_vino         INTEGER  NOT NULL,
    cantidad         INTEGER  NOT NULL,                          -- CHECK >= 0 en 002
    CONSTRAINT pk_stock_deposito PRIMARY KEY (cod_vino),
    CONSTRAINT fk_sd_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT
);

COMMIT;
