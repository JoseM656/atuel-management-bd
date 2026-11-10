# Informe de la Etapa 2: Integridad y Lógica · Bodegas del Atuel

> Trabajo Práctico Integrador · Bases de Datos · Ingeniería en Sistemas · UTN Facultad Regional San Rafael · Ciclo 2026.

---

## 1. Introducción y Alcance de la Etapa 2

La Etapa 2 representa el **núcleo funcional y de integridad del sistema (70% de la nota de la capa de datos)**. En esta etapa se implementaron todos los mecanismos de control transaccional, reglas de negocio explícitas (**RN-01 a RN-15**) e implícitas (**RI-01 a RI-07**), vistas analíticas y operativas, modelo de roles de seguridad con privilegios mínimos, y el banco de pruebas automáticas en SQL.

Los entregables correspondientes a esta etapa son:
1. `db/migrations/002_constraints.sql`: Restricciones de integridad adicionales (`UNIQUE`, `CHECK`, `DEFAULT`).
2. `db/migrations/003_funciones.sql`: Funciones de cálculo de stock, totales, antigüedad y descuentos.
3. `db/migrations/004_procedimientos.sql`: Procedimientos almacenados transaccionales para procesamiento de ingresos y transferencias.
4. `db/migrations/005_triggers.sql`: Triggers de protección de reglas de negocio (RN-05, RN-08, RN-09, RN-10, RN-11, RN-12, RN-13 y RI-01 a RI-06).
5. `db/migrations/006_vistas.sql`: Vistas de stock total, ventas mensuales (materializada), documentos pendientes y unificación de clientes.
6. `db/migrations/007_roles.sql`: Definición de roles (`app_rw`, `reportes_ro`) y asignación de privilegios mínimos.
7. `db/tests/db_tests.sql`: Script completo de pruebas de aceptación (casos válidos y casos inválidos esperados).

---

## 2. Cobertura de Reglas de Negocio (RN y RI) y Criterio de Ubicación

### 2.1 Guía Justificada: «¿Dónde va cada regla?»

La elección del mecanismo dentro de PostgreSQL sigue el principio de **utilizar la restricción declarativa más simple posible** y reservar PL/pgSQL (funciones, triggers y procedimientos) para las reglas que cruzan filas, tablas o estados temporales:

| Tipo de regla | Herramienta en PostgreSQL | Justificación técnica | Ejemplo en «Bodegas del Atuel» |
| :--- | :--- | :--- | :--- |
| **Valor válido de una sola fila, determinístico** | `NOT NULL`, `CHECK`, `DOMAIN`, `ENUM` | El motor lo evalúa en C de forma inmediata en cada `INSERT`/`UPDATE`, sin sobrecarga de contexto PL/pgSQL. | `ck_vino_precio CHECK (precio > 0)`, `DOMAIN cuit`, `ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision)`. |
| **Existencia de un dato relacionado y política de borrado** | `FOREIGN KEY` (`ON DELETE RESTRICT` / `CASCADE`, `ON UPDATE CASCADE`) | Garantiza integridad referencial a nivel de índice primario y bloquea bajas con historial (`RN-14`). | `fk_rc_vino (ON DELETE RESTRICT)`, `fk_rc_comprobante (ON DELETE CASCADE)`. |
| **Unicidad simple, compuesta o calculada sobre la fila** | `PRIMARY KEY`, `UNIQUE` o índice único de expresión | Resuelve unicidad en $O(\log N)$ mediante árbol B-Tree y soporta inserciones concurrentes sin condiciones de carrera. | `uq_vino_nombre_anada_volumen`, `idx_lote_uva_parcela_campana ON lote_uva (id_finca, nro_parcela, EXTRACT(YEAR FROM fecha_cosecha))`. |
| **Regla que depende de otras filas, otras tablas o de `CURRENT_DATE`** | `TRIGGER` (`BEFORE`, `AFTER` o `CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED`) | PostgreSQL prohíbe subconsultas en `CHECK`, y usar `CURRENT_DATE` en un `CHECK` rompería futuros `pg_restore` cuando el tiempo avance. Los triggers diferidos permiten validar invariantes globales al `COMMIT` (como sumas de porcentajes o relaciones N:M obligatorias). | `trg_renglon_comprobante_bi` (stock y copia de precio), `trg_composicion_suma_100` (`DEFERRABLE`), `trg_transferencia_fecha`. |
| **Cálculo reutilizable en múltiples consultas y triggers** | `FUNCTION` (`STABLE` / `IMMUTABLE`) | Centraliza una fórmula en un único punto del esquema, invocable tanto desde triggers como desde `SELECT`/`UPDATE`. | `fn_descuento_cliente`, `fn_total_comprobante`, `fn_stock_sala`, `fn_antiguedad_anios`. |
| **Operación de varios pasos que debe ser atómica (todo o nada)** | `PROCEDURE` transaccional con bloqueo pesimista (`FOR UPDATE`) | Encapsula la lectura con bloqueo de filas, el movimiento de inventarios entre tablas y la transición de estado en una sola llamada `CALL`. | `sp_procesar_ingreso`, `sp_procesar_transferencia`, `sp_terminar_ingreso`, `sp_terminar_transferencia`. |
| **Formato HTTP, experiencia de usuario y traducción legible** | API REST (`internal/httperr`) y Frontend | Traduce los códigos `SQLSTATE` (`23505`, `23503`, `23514`, `P0001`) a códigos HTTP (`409`, `422`, `400`) y muestra el motivo al usuario sin duplicar cálculos. | `httperr.Write` en Go + banner de errores en Alpine.js. |

### 2.2 Tabla de Trazabilidad Completa: `Regla → Mecanismo → Caso de Prueba`

Todas las reglas explícitas (**RN-01 a RN-15**) e implícitas (**RI-01 a RI-07**) están implementadas en [`db/migrations/`](../../../db/migrations/) y verificadas automáticamente en [`db/tests/db_tests.sql`](../../../db/tests/db_tests.sql) y [`api/internal/httpapi/api_test.go`](../../../api/internal/httpapi/api_test.go):

| Código | Regla de Negocio / Integridad | Mecanismo Exacto en la Base de Datos (`001`–`005`) | Caso de Prueba en `db/tests/db_tests.sql` y `api_test.go` |
| :--- | :--- | :--- | :--- |
| **RN-01** | El precio de un vino es único para toda la red de salas y siempre mayor que cero. | Columna `vino.precio` en tabla central + `ck_vino_precio CHECK (precio > 0)` + `uq_vino_nombre_anada_volumen UNIQUE (nombre, anada, volumen_ml)` (`002_constraints.sql:73,77`). | `debe_fallar('RN-01 precio 0')` (`db_tests.sql:135`) · `TestPrecioNegativo` y `TestMensajeVinoDuplicado` (`api_test.go`). |
| **RN-02** | Una sala pertenece a una sola localidad. Cada localidad tiene un único encargado regional. | `sala_venta.id_localidad NOT NULL` + `fk_sala_localidad` + `localidad.cuit_encargado NOT NULL` + `uq_localidad_encargado UNIQUE (cuit_encargado)` (`001_esquema.sql`, `002_constraints.sql:27`). | `debe_fallar('RN-02 sala con localidad inexistente')` y `debe_fallar('RN-02 mismo encargado en 2 localidades')` (`db_tests.sql:137-138`). |
| **RN-03** | Cada empleado trabaja en una sola sala. | Columna escalar `empleado.id_sala INTEGER NOT NULL` + `fk_empleado_sala REFERENCES sala_venta(id_sala) ON DELETE RESTRICT` (`001_esquema.sql`). | `debe_fallar('RN-03 empleado sin sala')` (`db_tests.sql:140`). |
| **RN-04** | Una parcela tiene una sola cepa y se cosecha como máximo una vez por campaña. | `parcela.id_cepa NOT NULL` + `fk_parcela_cepa` + índice único de expresión `idx_lote_uva_parcela_campana ON lote_uva (id_finca, nro_parcela, (EXTRACT(YEAR FROM fecha_cosecha)::INTEGER))` (`002_constraints.sql:60`). | `debe_fallar('RN-04 dos cosechas en 2024')` y `debe_funcionar('RN-04 cosechas en años distintos')` (`db_tests.sql:144,147`). |
| **RN-05** | Los porcentajes de corte de un vino suman exactamente 100. | `ck_composicion_porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100)` + constraint trigger diferido `trg_composicion_suma_100` (`DEFERRABLE INITIALLY DEFERRED`, `005_triggers.sql:541`). | `debe_fallar('RN-05 composición suma 95')` y `debe_funcionar('RN-05 cambiar corte a 80/20')` (`db_tests.sql:152-153`) · `TestEditarVinoComposicion` (`api_test.go`). |
| **RN-06** | El descuento depende del tipo de cliente: socio 10 %, distribuidor 20 %, exportador 30 %. | Función `fn_descuento_cliente(id_cliente)` (`003_funciones.sql`) + trigger `trg_cliente_descuento` (`BEFORE INSERT OR UPDATE ON cliente`, `005_triggers.sql:192`) + `ck_cliente_descuento CHECK (descuento BETWEEN 0 AND 35)` (`002_constraints.sql:96`). | `debe_funcionar('RN-06 descuentos 10/20/30')` y `debe_fallar('RN-06 descuento 50 a mano')` (`db_tests.sql:160,162`). |
| **RN-07** | Un exportador puede tener varios permisos; el vencimiento es posterior a la emisión. | Tabla `permiso_exportacion` con `fk_permiso_exportador REFERENCES exportador(id_cliente)` + `ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision)` (`002_constraints.sql:115`). | `debe_fallar('RN-07 vence antes de emitirse')` (`db_tests.sql:167`). |
| **RN-08** | El total del comprobante es la suma de sus renglones con el descuento aplicado. No se carga a mano. | Función `fn_total_comprobante(nro)` + triggers `trg_comprobante_descuento`, `trg_comprobante_importes`, `trg_comprobante_propaga_descuento`, `trg_renglon_comprobante_bi`, `trg_renglon_comprobante_ai` y `trg_renglon_comprobante_bud` (`005_triggers.sql:84-271`). | `debe_funcionar('RN-08 total de una venta')`, `debe_fallar('RN-08 pisar el total a mano')`, `debe_fallar('RN-08 pisar el subtotal a mano')`, `debe_funcionar('RN-08 U1: cambiar el descuento recalcula el total')`, `debe_fallar('RN-08 borrar un renglón suelto')` (`db_tests.sql:169-203`). |
| **RN-09** | No se puede vender más de lo que hay en stock de la sala. El stock nunca es negativo. | Función `fn_stock_sala(id_sala, cod_vino)` + bloqueo `SELECT ... FOR UPDATE` en `trg_renglon_comprobante_bi` + descuento en `trg_renglon_comprobante_ai` + `ck_stock_sala_cantidad CHECK (cantidad >= 0)` y `ck_stock_deposito_cantidad CHECK (cantidad >= 0)` (`002_constraints.sql:156,160`, `005_triggers.sql:84,121`). | `debe_fallar('RN-09 vender 2 con stock 1')`, `debe_funcionar('RN-09 vender todo el stock deja 0')`, `debe_fallar('RN-09 stock negativo a mano')` (`db_tests.sql:214-221`) · `TestVentaSinStock` (`api_test.go`). |
| **RN-10** | Sólo un ingreso terminado impacta en el depósito y pasa a procesado. Transiciones `en_confeccion → terminado → procesado` sin retrocesos. | `ENUM estado_documento` + `trg_ingreso_estado` (`005_triggers.sql:316`, exige flag `atuel.procesando_ingreso` para pasar a `procesado`) + procedimientos `sp_terminar_ingreso` y `sp_procesar_ingreso` (`004_procedimientos.sql`). | 7 casos en `db_tests.sql:223-241` (`procesar ingreso en confección`, `procesar ingreso terminado`, `retroceder terminado -> en_confeccion`, `saltar en_confeccion -> procesado`, `crear ingreso ya procesado`, `pasar a procesado sin el procedimiento`). |
| **RN-11** | Igual que RN-10 para transferencias. La fecha de confección es la actual y no se puede modificar. | `trg_transferencia_estado` (`005_triggers.sql:320`) + `trg_transferencia_fecha` (`005_triggers.sql:338`) + procedimientos `sp_terminar_transferencia` y `sp_procesar_transferencia` (`004_procedimientos.sql`). | 7 casos en `db_tests.sql:233-244` (`procesar sin stock suficiente`, `procesar transferencia OK`, `fecha de confección forzada a hoy`, `modificar fecha de confección`, `sin stock no deja nada a medias`) · `TestCambioEstadoInvalido` (`api_test.go`). |
| **RN-12** | Un ingreso o una transferencia que no está en confección no admite agregar, modificar ni quitar renglones. | Triggers `trg_renglon_ingreso_doc` (`005_triggers.sql:379`) y `trg_renglon_transferencia_doc` (`005_triggers.sql:415`) en `BEFORE INSERT OR UPDATE OR DELETE`. | `debe_fallar('RN-12 agregar renglón a transferencia terminada')`, `debe_fallar('RN-12 borrar renglón de ingreso terminado')`, `debe_funcionar('RN-12 editar renglón en confección')` (`db_tests.sql:248-250`) · `TestQuitarRenglonTransferencia` (`api_test.go`). |
| **RN-13** | Todo cambio de precio de un vino queda auditado (fecha, usuario, precio anterior y nuevo). | Tabla `auditoria_precio` + trigger `trg_vino_auditoria_precio` (`AFTER UPDATE OF precio ON vino`, `005_triggers.sql:435`). | `debe_funcionar('RN-13 cambio de precio auditado')` (`db_tests.sql:253`). |
| **RN-14** | No se puede borrar un transportista, una bodega ni un vino que tengan movimientos asociados. | Claves foráneas declaradas con `ON DELETE RESTRICT` (`fk_ingreso_transportista`, `fk_vino_bodega`, `fk_lote_bodega`, `fk_ingreso_bodega`, `fk_rc_vino`, `fk_ri_vino`, `fk_rt_vino`, `fk_stock_sala_vino`, `fk_stock_dep_vino`, `fk_auditoria_vino`). | `debe_fallar('RN-14 borrar transportista con ingresos')`, `debe_fallar('RN-14 borrar bodega con vinos')`, `debe_fallar('RN-14 borrar vino con movimientos')` (`db_tests.sql:256-258`) · `TestMensajeBorradoRN14` (`api_test.go`). |
| **RN-15** | Cantidades, superficies, kilos y precios son siempre positivos. La graduación está entre 5 y 20. | `CHECK` constraints en `002_constraints.sql`: `ck_vino_graduacion` (`5..20`), `ck_vino_precio`, `ck_finca_superficie`, `ck_parcela_superficie`, `ck_lote_kg`, `ck_rc_cantidad`, `ck_ri_cantidad`, `ck_rt_cantidad`, `ck_empleado_salario`. | `debe_fallar('RN-15 graduación 25')`, `debe_fallar('RN-15 cantidad 0 en renglón')`, `debe_fallar('RN-15 kilos negativos')` (`db_tests.sql:260-262`). |
| **RI-01** | El encargado regional trabaja en una sala de su misma localidad. | FK diferible `fk_localidad_encargado` + 3 constraint triggers diferidos: `trg_encargado_localidad`, `trg_encargado_empleado` y `trg_encargado_sala` (`005_triggers.sql:589-599`). | `debe_fallar('RI-01 encargado en sala de otra localidad')` (`db_tests.sql:142`). |
| **RI-02** | Todo vino tiene al menos un maridaje recomendado. | Constraint triggers diferidos `trg_vino_maridaje_obligatorio` (`AFTER INSERT ON vino`) y `trg_vino_maridaje_borrado` (`AFTER DELETE OR UPDATE ON vino_maridaje`) (`005_triggers.sql:561,566`). | `debe_fallar('RI-02 vino sin maridaje')` (`db_tests.sql:264`). |
| **RI-03** | El precio unitario en el renglón de venta es una copia histórica de `vino.precio` al momento de la operación. | `trg_renglon_comprobante_bi` asigna `NEW.precio_unitario := v_precio` leyendo `vino.precio` antes de insertar el renglón (`005_triggers.sql:84`). | `debe_funcionar('RI-03 copia histórica precio unitario')` (`db_tests.sql:265`). |
| **RI-04** | Los vinos incluidos en un ingreso pertenecen a la bodega de origen declarada en la cabecera. | Trigger `trg_renglon_ingreso_bodega` (`BEFORE INSERT OR UPDATE ON renglon_ingreso`, `005_triggers.sql:463`). | `debe_fallar('RI-04 vino de otra bodega en el ingreso')` (`db_tests.sql:270`). |
| **RI-05** | El transportista asignado a un ingreso cubre la localidad donde se ubica el depósito central. | Trigger `trg_ingreso_transportista` (`BEFORE INSERT OR UPDATE ON ingreso`, `005_triggers.sql:487`) verificando `transportista_localidad` contra `deposito.id_localidad`. | `debe_fallar('RI-05 transportista que no cubre el depósito')` (`db_tests.sql:271`). |
| **RI-06** | Un exportador con más de 3 permisos de exportación recibe un 35 % de descuento. | Función `fn_descuento_cliente` + trigger `trg_permiso_descuento` (`AFTER INSERT OR UPDATE OR DELETE ON permiso_exportacion`, `005_triggers.sql:517`). | `debe_funcionar('RI-06 exportador con 4 permisos -> 35')` (`db_tests.sql:163`). |
| **RI-07** | La jerarquía de clientes es total y disjunta: el subtipo coincide con `cliente.tipo` y todo cliente tiene su fila en la tabla de subtipo. | `uq_cliente_id_tipo UNIQUE (id_cliente, tipo)` + FKs compuestas `fk_socio_cliente`, `fk_distribuidor_cliente`, `fk_exportador_cliente` + `ck_socio_tipo`, `ck_distribuidor_tipo`, `ck_exportador_tipo` + constraint trigger diferido `trg_cliente_subtipo` (`005_triggers.sql:623`). | `debe_fallar('RI-07 subtipo no coincide con supertipo')` (`db_tests.sql:272`). |

---

## 3. Demo de Concurrencia (Gestión de la Última Botella)

### 3.1 Planteo del Problema y Concurrencia
En sistemas transaccionales con alta concurrencia de ventas (como una red de salas de venta distribuidas), dos cajeros podrían intentar vender simultáneamente la última botella disponible de un vino (`stock = 1`). 

Sin el control de concurrencia adecuado (bajo el nivel de aislamiento por defecto de PostgreSQL `Read Committed`), ambas sesiones leerían `stock = 1` en su consulta inicial, validarían que la cantidad solicitada (`1`) es menor o igual al stock disponible, y procederían a descontar el stock, provocando una **sobreventa** (stock negativo o inconsistencia de inventario).

### 3.2 Solución Implementada: `SELECT … FOR UPDATE`
Para evitar esta condición de carrera, los triggers y procedimientos del sistema bloquean exclusivamente la fila correspondiente en la tabla de stock mediante la cláusula `FOR UPDATE`:
```sql
PERFORM 1
FROM stock_sala
WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino
FOR UPDATE;
```

### 3.3 Simulación en dos sesiones `psql` (Capturas Reales de Terminal)

A continuación se adjunta la transcripción de la ejecución concurrente en dos terminales `psql` independientes demostrando el bloqueo y rechazo de la sobreventa:

#### **Sesión A (Cajero 1)**
```sql
atuel=# BEGIN;
BEGIN
atuel=*# INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, total, porcentaje_descuento) 
atuel-*# VALUES (CURRENT_DATE, 1, 1, 0, 0, 10.00);
INSERT 0 1
atuel=*# INSERT INTO renglon_comprobante (nro, cod_vino, cantidad, precio_unitario, subtotal, importe_descuento) 
atuel-*# VALUES (currval('comprobante_nro_seq'), 1, 1, 3000.00, 3000.00, 300.00);
INSERT 0 1
atuel=*# COMMIT;
COMMIT
```

#### **Sesión B (Cajero 2 - Intentando vender simultáneamente la misma última botella)**
```sql
atuel=# BEGIN;
BEGIN
atuel=*# INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, total, porcentaje_descuento) 
atuel-*# VALUES (CURRENT_DATE, 1, 1, 0, 0, 10.00);
INSERT 0 1
atuel=*# INSERT INTO renglon_comprobante (nro, cod_vino, cantidad, precio_unitario, subtotal, importe_descuento) 
atuel-*# VALUES (currval('comprobante_nro_seq'), 1, 1, 3000.00, 3000.00, 300.00);
-- [SESIÓN B QUEDA EN ESPERA / BLOQUEADA HASTA QUE SESIÓN A HACE COMMIT]
-- ... Tras el COMMIT de Sesión A, Sesión B adquiere el bloqueo y recibe:
ERROR:  stock insuficiente del vino 1 en la sala 1: hay 0 y se piden 1
CONTEXT:  PL/pgSQL function trg_fn_renglon_comprobante_bi() line 18 at RAISE
atuel=!# ROLLBACK;
ROLLBACK
```

---

## 4. Conclusiones

La implementación de la lógica en la base de datos (capa de datos como corazón del sistema) garantiza que **las reglas de negocio son inviolables**, protegiendo la integridad de la información sin importar si el acceso se realiza desde la API Go, desde la interfaz web Alpine.js, o directamente mediante clientes SQL (`psql`, DBeaver).
