-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- consultas/insert.sql — Etapa 5 · Inserciones (I1–I6)
--
-- Cada consigna lleva: código, enunciado, estrategia y los triggers,
-- funciones o constraints que intervienen. Todas se prueban en
-- transacción (BEGIN ... SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK)
-- forzando la evaluación de los constraint triggers diferidos
-- (DEFERRABLE INITIALLY DEFERRED) y mostrando el estado antes y después.
--
-- Nota sobre ROLLBACK y secuencias IDENTITY: el ROLLBACK revierte todas
-- las filas insertadas dejando las tablas intactas, pero en PostgreSQL
-- el avance de secuencias (nextval sobre columnas GENERATED ALWAYS AS
-- IDENTITY) no es transaccional, por lo que los IDs consumidos durante
-- la prueba no se revierten en el contador de la secuencia.
--
-- Requisito: base cargada con db/seed/seed.py (semilla 42) y migraciones
-- 001–008 aplicadas. Las fechas son relativas a CURRENT_DATE.
-- =====================================================================

\pset pager off
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Parámetros de ejecución (con valores por defecto del dataset seed=42).
-- Permite ejecutar directamente:
--   psql -f consultas/insert.sql
-- O sobreescribir cualquier parámetro por línea de comandos:
--   psql -v cliente_i3=15 -v vino_i6=4 -f consultas/insert.sql
-- ---------------------------------------------------------------------
\if :{?cliente_i3}       \else \set cliente_i3 1                                          \endif
\if :{?vino1_i3}         \else \set vino1_i3 1                                            \endif
\if :{?vino2_i3}         \else \set vino2_i3 2                                            \endif
\if :{?vino3_i3}         \else \set vino3_i3 3                                            \endif
\if :{?cuit_bodega_i4}   \else \set cuit_bodega_i4 '30710000219'                          \endif
\if :{?razon_bodega_i4}  \else \set razon_bodega_i4 'Bodega Finca Los Andes S.A.'         \endif
\if :{?dom_bodega_i4}    \else \set dom_bodega_i4 'Ruta Nacional 143 Km 512, San Rafael'  \endif
\if :{?localidad_i5}     \else \set localidad_i5 'San Rafael'                             \endif
\if :{?calle_i5}         \else \set calle_i5 'Av. Hipólito Yrigoyen'                      \endif
\if :{?numero_i5}        \else \set numero_i5 '1450'                                      \endif
\if :{?dia_cierre_i5}    \else \set dia_cierre_i5 'lunes'                                 \endif
\if :{?vino_i6}          \else \set vino_i6 1                                             \endif
\if :{?transportista_i6} \else \set transportista_i6 1                                    \endif

-- =====================================================================
-- I1 · Insertar en la relación transportista-localidad una nueva
--      cobertura que vincule la localidad de General Alvear con el
--      transportista que menos envíos (ingresos trasladados) haya
--      realizado en el último trimestre
--
-- Estrategia: se resuelve la localidad «General Alvear» y se cuentan los
-- ingresos registrados en los últimos 3 meses por transportista usando
-- LEFT JOIN con el filtro de fecha en el ON (para conservar con 0 a los
-- transportistas sin envíos en el trimestre).
--   · Criterio sobre NOT EXISTS: se restringe la selección a los
--     transportistas que aún no cubren General Alvear para que el INSERT
--     registre una cobertura nueva sin colisionar con
--     pk_transportista_localidad (además, con seed=42 el transportista 15
--     tiene 0 envíos tanto a nivel global como entre quienes no cubren
--     dicha localidad).
--   · Criterio sobre ingreso.estado: se contabilizan todos los ingresos
--     del trimestre (en línea con S7 de consultas/select.sql); con
--     seed=42, filtrar adicionalmente por i.estado = 'procesado' arroja
--     exactamente el mismo resultado (transportista 15 con 0 envíos).
--
-- Triggers/constraints que intervienen:
--   · pk_transportista_localidad (cod_transportista, id_localidad):
--     impide duplicar una cobertura ya existente.
--   · fk_tl_transportista (ON DELETE CASCADE) y fk_tl_localidad
--     (ON DELETE RESTRICT).
--   · Esta tabla es consultada por trg_ingreso_transportista (RN-06) al
--     validar ingresos al depósito.
-- =====================================================================
\echo '=== I1: nueva cobertura en General Alvear con el transportista con menos envíos en el trimestre ==='
BEGIN;

SELECT count(*) AS coberturas_alvear_antes
FROM transportista_localidad tl
JOIN localidad l ON l.id_localidad = tl.id_localidad
WHERE l.nombre = 'General Alvear';

INSERT INTO transportista_localidad (cod_transportista, id_localidad)
SELECT
    t.cod_transportista,
    l.id_localidad
FROM transportista t
CROSS JOIN localidad l
LEFT JOIN ingreso i
       ON i.cod_transportista = t.cod_transportista
      AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
WHERE l.nombre = 'General Alvear'
  AND NOT EXISTS (
      SELECT 1
      FROM transportista_localidad tl
      WHERE tl.cod_transportista = t.cod_transportista
        AND tl.id_localidad = l.id_localidad
  )
GROUP BY t.cod_transportista, l.id_localidad
ORDER BY count(i.cod_ingreso) ASC, t.cod_transportista ASC
LIMIT 1;

SELECT
    tl.cod_transportista,
    t.razon_social,
    l.nombre AS localidad,
    count(*) OVER () AS coberturas_alvear_despues
FROM transportista_localidad tl
JOIN transportista t ON t.cod_transportista = tl.cod_transportista
JOIN localidad l ON l.id_localidad = tl.id_localidad
WHERE l.nombre = 'General Alvear'
ORDER BY tl.cod_transportista;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

-- =====================================================================
-- I2 · Si existe algún vino tinto con graduación de 14° o más, crear el
--      maridaje «cordero al disco» y asociarlo a todos los vinos que
--      cumplan esa condición
--
-- Estrategia: mediante un CTE modificador (WITH nuevo_maridaje AS ...) se
-- inserta el maridaje «cordero al disco» únicamente si WHERE EXISTS
-- detecta al menos un vino con tipo = 'tinto' y graduacion >= 14,
-- recuperando su id_maridaje con RETURNING. En la misma sentencia se
-- insertan en vino_maridaje los pares (cod_vino, id_maridaje) para todos
-- los vinos que cumplen la condición.
--
-- Triggers/constraints que intervienen:
--   · pk_maridaje, uq_maridaje_nombre UNIQUE (nombre) y
--     ck_maridaje_temperatura CHECK (temperatura_servicio BETWEEN 0 AND 25).
--   · pk_vino_maridaje (cod_vino, id_maridaje), fk_vm_vino
--     (ON DELETE CASCADE) y fk_vm_maridaje (ON DELETE RESTRICT).
--   · trg_vino_maridaje_obligatorio (RI-02, DEFERRABLE INITIALLY DEFERRED):
--     verifica al ejecutar SET CONSTRAINTS ALL IMMEDIATE que todo vino
--     tenga al menos un maridaje asociado.
-- =====================================================================
\echo '=== I2: crear maridaje «cordero al disco» si existe tinto >= 14° y asociarlo ==='
BEGIN;

SELECT
    count(*) AS tintos_14_o_mas,
    (SELECT count(*) FROM maridaje WHERE lower(nombre) = 'cordero al disco') AS maridaje_antes
FROM vino
WHERE tipo = 'tinto' AND graduacion >= 14;

WITH nuevo_maridaje AS (
    INSERT INTO maridaje (nombre, temperatura_servicio)
    SELECT 'cordero al disco', 17.0
    WHERE EXISTS (
        SELECT 1
        FROM vino
        WHERE tipo = 'tinto' AND graduacion >= 14
    )
    RETURNING id_maridaje
)
INSERT INTO vino_maridaje (cod_vino, id_maridaje)
SELECT v.cod_vino, nm.id_maridaje
FROM vino v
CROSS JOIN nuevo_maridaje nm
WHERE v.tipo = 'tinto' AND v.graduacion >= 14;

SELECT
    m.id_maridaje,
    m.nombre,
    m.temperatura_servicio,
    count(vm.cod_vino) AS vinos_asociados_despues
FROM maridaje m
JOIN vino_maridaje vm ON vm.id_maridaje = m.id_maridaje
WHERE lower(m.nombre) = 'cordero al disco'
GROUP BY m.id_maridaje, m.nombre, m.temperatura_servicio;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

-- =====================================================================
-- I3 · Crear un nuevo comprobante con tres renglones para un cliente
--      dado, en la sala con ID 1, dentro de una transacción y usando las
--      funciones de cálculo
--
-- Estrategia: se consulta la disponibilidad previa con fn_stock_sala() y
-- se inserta la cabecera en comprobante indicando únicamente
-- (id_cliente, id_sala), delegando fecha, subtotal, total y
-- porcentaje_descuento en los valores DEFAULT y en el trigger
-- trg_comprobante_descuento. Luego se insertan los 3 renglones en
-- renglon_comprobante indicando solo (nro, cod_vino, cantidad); los
-- triggers BEFORE/AFTER INSERT completan precio_unitario,
-- importe_descuento y subtotal del renglón, descuentan el stock en sala y
-- recalculan subtotal y total de la cabecera con fn_total_comprobante().
--
-- Funciones, triggers y constraints que intervienen:
--   · fn_descuento_cliente(id_cliente): calcula el % de descuento según
--     subtipo y cantidad de permisos (RN-07, RI-06).
--   · fn_stock_sala(id_sala, cod_vino): devuelve el stock actual en sala.
--   · fn_total_comprobante(nro): calcula el total neto del comprobante.
--   · trg_comprobante_descuento (BEFORE INSERT ON comprobante, RN-07):
--     asigna automáticamente NEW.porcentaje_descuento invocando
--     fn_descuento_cliente(NEW.id_cliente).
--   · trg_renglon_comprobante_bi (BEFORE INSERT, RN-08/RN-09/RI-03):
--     bloquea la fila en stock_sala con FOR UPDATE, verifica stock
--     suficiente, copia vino.precio como precio_unitario histórico y
--     calcula importe_descuento y subtotal del renglón antes de evaluar
--     las restricciones NOT NULL y CHECK.
--   · trg_renglon_comprobante_ai (AFTER INSERT, RN-08/RN-09): descuenta
--     la cantidad vendida en stock_sala y recalcula subtotal y total en
--     comprobante usando fn_total_comprobante(NEW.nro).
-- =====================================================================
\echo '=== I3: nuevo comprobante de 3 renglones en sala 1 usando funciones de cálculo ==='
BEGIN;

SELECT
    c.id_cliente,
    c.nombre_razon_social,
    c.tipo,
    fn_descuento_cliente(c.id_cliente) AS descuento_calculado
FROM cliente c
WHERE c.id_cliente = :'cliente_i3';

SELECT
    v.cod_vino,
    v.nombre,
    v.precio AS precio_catalogo,
    fn_stock_sala(1, v.cod_vino) AS stock_sala_1_antes
FROM vino v
WHERE v.cod_vino IN (:'vino1_i3', :'vino2_i3', :'vino3_i3')
ORDER BY v.cod_vino;

INSERT INTO comprobante (id_cliente, id_sala)
VALUES (:'cliente_i3', 1);

INSERT INTO renglon_comprobante (nro, cod_vino, cantidad)
VALUES
    (currval(pg_get_serial_sequence('comprobante', 'nro')), :'vino1_i3', 2),
    (currval(pg_get_serial_sequence('comprobante', 'nro')), :'vino2_i3', 1),
    (currval(pg_get_serial_sequence('comprobante', 'nro')), :'vino3_i3', 3);

SELECT
    co.nro,
    co.fecha,
    co.id_cliente,
    co.id_sala,
    co.subtotal,
    co.porcentaje_descuento,
    co.total AS total_comprobante,
    fn_total_comprobante(co.nro) AS total_via_funcion
FROM comprobante co
WHERE co.nro = currval(pg_get_serial_sequence('comprobante', 'nro'));

SELECT
    rc.cod_vino,
    rc.cantidad,
    rc.precio_unitario,
    rc.importe_descuento,
    rc.subtotal,
    fn_stock_sala(1, rc.cod_vino) AS stock_sala_1_despues
FROM renglon_comprobante rc
WHERE rc.nro = currval(pg_get_serial_sequence('comprobante', 'nro'))
ORDER BY rc.cod_vino;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

-- =====================================================================
-- I4 · Insertar una nueva bodega
--
-- Estrategia: inserción directa en bodega con CUIT, razón social y
-- domicilio parametrizados (:cuit_bodega_i4, :razon_bodega_i4,
-- :dom_bodega_i4).
--
-- Triggers/constraints que intervienen:
--   · DOMAIN cuit: valida 11 dígitos numéricos (CHAR(11), ^[0-9]{11}$).
--   · pk_bodega (cuit) y NOT NULL en razon_social y domicilio.
-- =====================================================================
\echo '=== I4: insertar una nueva bodega ==='
BEGIN;

SELECT count(*) AS bodegas_antes FROM bodega;

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES (:'cuit_bodega_i4', :'razon_bodega_i4', :'dom_bodega_i4');

SELECT
    b.cuit,
    b.razon_social,
    b.domicilio,
    (SELECT count(*) FROM bodega) AS bodegas_despues
FROM bodega b
WHERE b.cuit = :'cuit_bodega_i4';

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

-- =====================================================================
-- I5 · Insertar una nueva sala de venta
--
-- Estrategia: se inserta una nueva fila en sala_venta vinculada a la
-- localidad elegida (:localidad_i5) mediante subconsulta escalar y
-- casteando el día de cierre al ENUM dia_semana.
--
-- Triggers/constraints que intervienen:
--   · pk_sala_venta (id_sala) y ck_sala_numero CHECK (numero > 0).
--   · fk_sala_localidad -> localidad(id_localidad) ON DELETE RESTRICT
--     (RN-02: toda sala pertenece a una localidad registrada).
--   · trg_encargado_sala, trg_encargado_localidad y
--     trg_encargado_empleado (RI-01, DEFERRABLE INITIALLY DEFERRED):
--     verifican al ejecutar SET CONSTRAINTS ALL IMMEDIATE que el
--     encargado regional trabaje en al menos una sala de esa localidad.
--   · ENUM dia_semana: valida el día de cierre semanal.
-- =====================================================================
\echo '=== I5: insertar una nueva sala de venta ==='
BEGIN;

SELECT count(*) AS salas_antes FROM sala_venta;

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES (
    :'calle_i5',
    :'numero_i5',
    (:'dia_cierre_i5')::dia_semana,
    (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_i5')
);

SELECT
    s.id_sala,
    s.calle,
    s.numero,
    s.dia_cierre,
    l.nombre AS localidad,
    l.cuit_encargado AS encargado_regional,
    (SELECT count(*) FROM sala_venta) AS salas_despues
FROM sala_venta s
JOIN localidad l ON l.id_localidad = s.id_localidad
WHERE s.id_sala = currval(pg_get_serial_sequence('sala_venta', 'id_sala'));

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

-- =====================================================================
-- I6 · Crear un ingreso en confección de 120 botellas de un vino
--      determinado, elaborado por una bodega dada y trasladado por un
--      transportista dado
--
-- Estrategia: mediante un CTE modificador (WITH nuevo_ingreso AS ...) se
-- crea la cabecera en ingreso con estado = 'en_confeccion', tomando la
-- bodega elaboradora directamente del vino elegido (:vino_i6) y el
-- transportista :transportista_i6. Con el cod_ingreso retornado por
-- RETURNING se inserta el renglón de 120 botellas en renglon_ingreso.
--
-- Triggers/constraints que intervienen:
--   · trg_ingreso_transportista (RN-06): verifica que el transportista
--     cubra la localidad donde está ubicado el depósito central
--     (San Rafael).
--   · trg_ingreso_estado (RN-10): exige que todo nuevo ingreso se cree
--     inicialmente en estado 'en_confeccion'.
--   · trg_renglon_ingreso_doc (RN-12): permite insertar el renglón solo
--     porque la cabecera está en estado 'en_confeccion'.
--   · trg_renglon_ingreso_bodega (RI-04): valida que el vino del renglón
--     pertenezca a la bodega declarada en la cabecera del ingreso.
--   · ck_ri_cantidad CHECK (cantidad > 0) (RN-15): valida cantidad > 0.
--   · RN-10: al crearse en estado 'en_confeccion', stock_deposito aún no
--     se modifica (recién impacta al ejecutar sp_procesar_ingreso).
-- =====================================================================
\echo '=== I6: ingreso en confección de 120 botellas de un vino dado ==='
BEGIN;

SELECT
    v.cod_vino,
    v.nombre AS vino,
    v.volumen_ml,
    v.cuit_bodega,
    sd.cantidad AS stock_deposito_antes
FROM vino v
LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
WHERE v.cod_vino = :'vino_i6';

WITH nuevo_ingreso AS (
    INSERT INTO ingreso (fecha, estado, cod_transportista, cuit_bodega)
    SELECT
        CURRENT_DATE,
        'en_confeccion'::estado_documento,
        :'transportista_i6',
        v.cuit_bodega
    FROM vino v
    WHERE v.cod_vino = :'vino_i6'
    RETURNING cod_ingreso
)
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT ni.cod_ingreso, :'vino_i6', 120
FROM nuevo_ingreso ni;

SELECT
    i.cod_ingreso,
    i.fecha,
    i.estado,
    i.cod_transportista,
    i.cuit_bodega,
    ri.cod_vino,
    v.nombre AS vino,
    ri.cantidad AS botellas_ingreso,
    sd.cantidad AS stock_deposito_despues
FROM ingreso i
JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
JOIN vino v ON v.cod_vino = ri.cod_vino
LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
WHERE i.cod_ingreso = currval(pg_get_serial_sequence('ingreso', 'cod_ingreso'));

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
