# Informe Final Integrador — Sistema de Gestión y Distribución «Bodegas del Atuel»

> **Trabajo Práctico Integrador · Bases de Datos · Ingeniería en Sistemas · UTN Facultad Regional San Rafael · Ciclo 2026**

---

## Índice General (Estructura según Sección 10.2)

1. [Introducción y alcance](#1-introducción-y-alcance)
2. [Modelo de datos](#2-modelo-de-datos)
   - [2.1 Diagrama Entidad-Relación (DER) y su funcionamiento](#21-diagrama-entidad-relación-der-y-su-funcionamiento)
   - [2.2 Esquema relacional y acciones referenciales](#22-esquema-relacional-y-acciones-referenciales)
   - [2.3 Normalización hasta 3FN](#23-normalización-hasta-3fn)
   - [2.4 Decisiones de diseño y diccionario de datos](#24-decisiones-de-diseño-y-diccionario-de-datos)
3. [Integridad y lógica en la base de datos](#3-integridad-y-lógica-en-la-base-de-datos)
   - [3.1 Guía justificada: «¿Dónde va cada regla?»](#31-guía-justificada-dónde-va-cada-regla)
   - [3.2 Tabla de trazabilidad Regla → Mecanismo → Caso de prueba](#32-tabla-de-trazabilidad-regla--mecanismo--caso-de-prueba)
   - [3.3 Modelo de roles y privilegios mínimos](#33-modelo-de-roles-y-privilegios-mínimos)
   - [3.4 Demostración de concurrencia (Gestión de la última botella)](#34-demostración-de-concurrencia-gestión-de-la-última-botella)
4. [Carga masiva de datos](#4-carga-masiva-de-datos)
5. [Índices y rendimiento](#5-índices-y-rendimiento)
6. [Consultas SQL](#6-consultas-sql)
7. [API REST y Frontend](#7-api-rest-y-frontend)
8. [Despliegue en la nube](#8-despliegue-en-la-nube)
9. [Conclusiones](#9-conclusiones)

---

## 1. Introducción y alcance

El presente informe documenta el diseño, implementación, optimización, pruebas y despliegue del sistema para **«Bodegas del Atuel»**, una empresa vitivinícola que integra toda su cadena de valor:
1. **Producción primaria de uva:** administración de fincas ubicadas en departamentos de Mendoza, división en parcelas (entidades débiles) plantadas con una cepa, registro de lotes de cosecha por campaña (máximo una cosecha por parcela y año) y análisis de calidad enológicos (Brix, pH y acidez total).
2. **Elaboración y catálogo de vinos:** gestión de bodegas del grupo, vinos por añada y presentación (`187` a `3000` ml), corte varietal con suma exacta del `100 %`, maridajes recomendados con temperatura de servicio y auditoría automática de cambios de precio.
3. **Logística e inventario:** recepción de producción embotellada en un único depósito central mediante **ingresos** trasladados por empresas transportistas con cobertura verificada, y abastecimiento a las **salas de venta** regionales mediante **transferencias**, bajo un ciclo de vida estricto (`en_confeccion → terminado → procesado`).
4. **Comercialización y ventas:** atención a una jerarquía total y disjunta de clientes (**socios**, **distribuidores** y **exportadores** con permisos de exportación) y emisión transaccional de **comprobantes de venta** con cálculo automático de precios históricos, descuentos escalonados (`10 %`, `20 %`, `30 %`, `35 %`) y control concurrente de stock.

El principio rector de la arquitectura es la **Regla de Oro**: **la base de datos PostgreSQL 16 es el corazón del sistema y la única responsable de garantizar la integridad y los cálculos de negocio**. Ni la API REST en Go ni el Frontend en Alpine.js utilizan ORM ni recalculan precios, descuentos, totales o stocks; delegan íntegramente en las restricciones, funciones, procedimientos y triggers del motor relacional.

---

## 2. Modelo de datos

### 2.1 Diagrama Entidad-Relación (DER) y su funcionamiento

![Diagrama Entidad-Relación de Bodegas del Atuel](entregables/etapa%201/DER.png)

*(Archivo fuente editable disponible en [`docs/entregables/etapa 1/DER_Bodegas_del_Atuel_V1.drawio`](entregables/etapa%201/DER_Bodegas_del_Atuel_V1.drawio) y guía extendida de defensa en [`docs/entregables/etapa 1/defensa_DER.md`](entregables/etapa%201/defensa_DER.md)).*

#### **Criterio general y notación**
Se adoptó la **notación de Chen con cardinalidades `(mín, máx)`** junto a cada entidad (indicando la participación de esa entidad en la relación), coloreada por subsistema funcional (producción, vinos, ventas, logística):
- Permite representar de forma puramente conceptual la **entidad débil** (`Parcela` con doble rectángulo y rombo identificador doble `posee`), la **jerarquía total y disjunta** (`Cliente` con círculo `d`) y las **relaciones N:M con atributos propios sobre el rombo** (`porcentaje` en composición, `cantidad` en stocks y renglones) sin convertirlas prematuramente en tablas intermedias como exigiría la notación pata de gallo (*crow's foot*).
- Se modeló pensando en **3FN desde el propio DER**: cuando un atributo habría generado una dependencia transitiva (como `departamento → provincia` en `Finca` o `localidad → encargado` en `Sala`), se promovió a entidad o relación independiente.

#### **Decisiones de modelado por bloque funcional**

1. **Ubicación y personal:**
   - **Localidad, Sala de venta y Empleado:** Una sala pertenece a una única localidad (`Sala (1,1)` — `Localidad (0,N)`). Cada empleado trabaja en una sola sala (`RN-03`, `Empleado (1,1)`), y en cada sala trabajan uno o varios empleados (`Sala (1,N)`).
   - **Encargado regional como relación con `Empleado`:** Tanto la sección 3.1 como `RN-02` establecen que por cada localidad existe un único encargado regional. Se modeló como `Localidad (1,1) — es encargado de — (0,1) Empleado` porque el encargado es un empleado con CUIT y no un texto libre, evitando además la dependencia transitiva `sala → localidad → encargado`.
   - **Departamento como entidad propia:** Separar `Departamento` elimina la dependencia transitiva `finca → departamento → provincia` y refleja el catálogo oficial de los 18 departamentos de Mendoza del Anexo B.

2. **Producción de uva:**
   - **Parcela como entidad débil:** Identificada por `(id_finca, nro_parcela)` mediante la relación identificadora `posee` con `Finca (1,N)`. Cada parcela tiene plantada una única cepa (`Parcela (1,1)` — `Cepa (0,N)`, `RN-04`).
   - **Lote de uva como entidad fuerte:** Posee número propio global (`nro_lote`), se vincula con su parcela de origen y con la bodega destino, y de él dependen los **análisis de calidad** con cardinalidad `(0,N)` (ya que el lote se registra al cosechar y los análisis de laboratorio se practican con posterioridad).
   - **Campaña derivada:** No se almacena como atributo redundante en `lote_uva`; se deriva del año de `fecha_cosecha` y la regla de una cosecha máxima por parcela y campaña (`RN-04`) se garantiza con el índice único de expresión `idx_lote_uva_parcela_campana`.

3. **Bodegas y vinos:**
   - **Bodega y sus tres roles:** Una bodega elabora vinos (`elabora`), recibe lotes de uva (`entregado a`) y origina ingresos al depósito (`genera`).
   - **Presentación (`volumen_ml`) como atributo del vino:** Cada combinación `(nombre, añada, volumen_ml)` tiene su propio código y precio de catálogo.
   - **Composición y Maridaje (`N:M`):** Todo vino se compone de una o más cepas (`Vino (1,N)` con atributo `porcentaje` sobre el rombo que suma `100 %`, `RN-05`) y se recomienda con al menos un maridaje (`Vino (1,N)`, `RI-02`).
   - **Auditoría de precio:** Entidad histórica alimentada automáticamente por trigger ante cada modificación de `vino.precio` (`RN-13`).

4. **Clientes y ventas:**
   - **Jerarquía total y disjunta (`(t, d)`):** Todo `Cliente` es exactamente un `Socio`, un `Distribuidor` o un `Exportador`. La relación con **`Permiso de exportación`** nace exclusivamente del subtipo **`Exportador`** (`Permiso (1,1)` — `Exportador (0,N)`, `RN-07`), impidiendo por diseño que un socio o distribuidor tenga permisos de exportación.
   - **Comprobante y Renglón (`N:M` con atributos):** Un comprobante vincula un cliente y una sala, y sus renglones registran `cantidad`, `precio_unitario` histórico (`RI-03`), `importe_descuento` y `subtotal` con clave `(nro, cod_vino)` (`RN-08`, `RN-09`).

5. **Stock y logística:**
   - **Depósito central y stocks simétricos:** `Deposito` se modela como entidad (`id = 1`) ubicada en una localidad (`San Rafael`), lo que permite que tanto `stock_sala` como `stock_deposito` sean relaciones con atributo `cantidad` y que el trigger de `RI-05` valide que el transportista de un ingreso cubra la localidad del depósito.
   - **Ingresos y Transferencias:** Se modelan como entidades con identidad, fecha y ciclo de estados (`RN-10`, `RN-11`, `RN-12`), cuyos renglones son relaciones `N:M` con `Vino`.

---

### 2.2 Esquema relacional y acciones referenciales

El DER se transforma en **31 tablas** y **37 claves foráneas** implementadas en [`db/migrations/001_esquema.sql`](../db/migrations/001_esquema.sql). El desarrollo completo de las 31 relaciones y la tabla de las 37 FKs se encuentran en [`docs/entregables/etapa 1/esquema_relacional_escrito.md`](entregables/etapa%201/esquema_relacional_escrito.md).

- **Criterio de `ON DELETE`:**
  - `ON DELETE CASCADE` **únicamente** en entidades débiles o filas que carecen de sentido sin su cabecera (`parcela`, `analisis_calidad`, `composicion`, `vino_maridaje`, `socio`, `distribuidor`, `exportador`, `permiso_exportacion`, `renglon_comprobante`, `renglon_ingreso`, `renglon_transferencia`, `transportista_localidad`).
  - `ON DELETE RESTRICT` en **todas las demás relaciones** (movimientos históricos, catálogos, bodegas, vinos, clientes, salas, empleados y auditoría), cumpliendo estrictamente **RN-14**.
- **Criterio de `ON UPDATE`:**
  - `ON UPDATE CASCADE` en las claves foráneas que referencian un `CUIT` (clave natural en `bodega` y `empleado`); `NO ACTION` en las claves subrogadas `GENERATED ALWAYS AS IDENTITY` que jamás mutan.

---

### 2.3 Normalización hasta 3FN

Las 31 relaciones cumplen **1FN, 2FN y 3FN** sin excepciones (justificación completa en [`esquema_relacional_escrito.md`](entregables/etapa%201/esquema_relacional_escrito.md#L100-L133)):
- **1FN:** Todos los atributos son atómicos; los multivaluados se descompusieron en tablas (`composicion`, `vino_maridaje`, `permiso_exportacion`, `renglon_*`).
- **2FN:** En todas las tablas con clave primaria compuesta (`parcela`, `composicion`, `renglon_comprobante`, `renglon_ingreso`, `renglon_transferencia`, `stock_sala`), cada atributo no primo depende de la clave compuesta completa. Por ejemplo, el `nombre` o el `precio` actual del vino vive en `vino(cod_vino)`, mientras que en `renglon_comprobante(nro, cod_vino)` solo vive el `precio_unitario` histórico de esa venta particular.
- **3FN:** Se eliminaron todas las dependencias transitivas potenciales:
  1. `id_sala → id_localidad → cuit_encargado`: el encargado se almacena en `localidad`, nunca en `sala_venta`.
  2. `id_finca → id_departamento → (nombre, provincia)`: el departamento se extrajo a la tabla `departamento`.
  3. `nro_lote → fecha_cosecha → campaña`: la campaña no se almacena como columna, evitando anomalías de actualización.

---

### 2.4 Decisiones de diseño y diccionario de datos

El análisis exhaustivo de las cinco decisiones de diseño de la Sección 5 se documenta en [`docs/entregables/etapa 1/desiciones_diseño.md`](entregables/etapa%201/desiciones_diseño.md) y el diccionario de datos de las 31 tablas en [`docs/entregables/etapa 1/diccionario_datos.md`](entregables/etapa%201/diccionario_datos.md):
1. **Jerarquía de clientes:** Estrategia *supertipo (`cliente`) + una tabla por subtipo (`socio`, `distribuidor`, `exportador`)* vinculadas por FK compuesta `(id_cliente, tipo)` con `CHECK` de tipo fijo en cada subtipo (**RI-07**) y constraint trigger diferido `trg_cliente_subtipo` para la totalidad. Evita columnas `NULL` y permite que `permiso_exportacion` referencie exclusivamente a `exportador(id_cliente)`.
2. **Claves naturales vs. subrogadas:** `CUIT` (`DOMAIN cuit AS CHAR(11)`) en `bodega` y `empleado`, `codigo` en `permiso_exportacion`, clave compuesta `(id_finca, nro_parcela)` en la entidad débil `parcela`, y `GENERATED ALWAYS AS IDENTITY` en el resto.
3. **Tipos de datos:** `NUMERIC(12,2)` para importes y salarios (jamás `FLOAT`), `NUMERIC(5,2)` para porcentajes, `DATE` para fechas operativas, `TIMESTAMPTZ` para `auditoria_precio`, y 5 tipos `ENUM` (`dia_semana`, `tipo_cepa`, `tipo_vino`, `tipo_cliente`, `estado_documento`).
4. **Atributos derivados:** Los 9 atributos derivados almacenados por historia o rendimiento (`comprobante.subtotal`, `porcentaje_descuento`, `total`; `renglon_comprobante.precio_unitario`, `importe_descuento`, `subtotal`; `cliente.descuento`; `stock_sala.cantidad`; `stock_deposito.cantidad`) se definen como columnas `NUMERIC` / `INTEGER NOT NULL` en [`001_esquema.sql`](../db/migrations/001_esquema.sql) y son calculados y protegidos exclusivamente por triggers (`trg_renglon_comprobante_bi`, `trg_renglon_comprobante_ai`, `trg_comprobante_importes`, `trg_comprobante_propaga_descuento`, `trg_renglon_comprobante_bud`, `trg_cliente_descuento`, `trg_permiso_descuento`), funciones (`fn_*`) y procedimientos (`sp_*`), impidiendo cualquier edición manual inconsistente.

---

## 3. Integridad y lógica en la base de datos

*(Informe detallado de la Etapa 2 en [`docs/entregables/etapa 2/informe_etapa2.md`](entregables/etapa%202/informe_etapa2.md)).*

### 3.1 Guía justificada: «¿Dónde va cada regla?»

| Tipo de regla | Herramienta en PostgreSQL | Justificación técnica | Ejemplo en el proyecto |
| :--- | :--- | :--- | :--- |
| **Valor válido de una sola fila, determinístico** | `NOT NULL`, `CHECK`, `DOMAIN`, `ENUM` | Evaluación nativa e inmediata sin sobrecarga PL/pgSQL. | `ck_vino_precio CHECK (precio > 0)`, `DOMAIN cuit`, `ck_permiso_fechas`. |
| **Existencia de un dato relacionado y política de baja** | `FOREIGN KEY` (`RESTRICT` / `CASCADE`) | Garantiza integridad referencial por índice y bloquea bajas con movimientos (`RN-14`). | `fk_rc_vino (ON DELETE RESTRICT)`, `fk_rc_comprobante (ON DELETE CASCADE)`. |
| **Unicidad simple, compuesta o sobre expresión** | `PRIMARY KEY`, `UNIQUE` o índice único de expresión | Resuelve unicidad en árbol B-Tree soportando concurrencia. | `uq_vino_nombre_anada_volumen`, `idx_lote_uva_parcela_campana`. |
| **Depende de otras filas, otras tablas o de `CURRENT_DATE`** | `TRIGGER` (`BEFORE`, `AFTER` o `CONSTRAINT TRIGGER DEFERRABLE`) | PostgreSQL no admite subconsultas en `CHECK`, y usar `CURRENT_DATE` en un `CHECK` rompería `pg_restore` futuros. Los triggers diferidos validan sumas o relaciones obligatorias al `COMMIT`. | `trg_renglon_comprobante_bi`, `trg_composicion_suma_100` (`DEFERRABLE`), `trg_transferencia_fecha`. |
| **Cálculo reutilizable en varios lugares** | `FUNCTION` (`STABLE` / `IMMUTABLE`) | Centraliza la fórmula en un solo objeto invocable desde SQL y triggers. | `fn_descuento_cliente`, `fn_total_comprobante`, `fn_stock_sala`, `fn_antiguedad_anios`. |
| **Operación multipaso atómica (todo o nada)** | `PROCEDURE` transaccional con `FOR UPDATE` | Bloquea filas, mueve stocks entre tablas y cambia el estado de forma atómica. | `sp_procesar_ingreso`, `sp_procesar_transferencia`. |
| **Traducción HTTP y experiencia de usuario** | API REST (`httperr`) y Frontend | Traduce `SQLSTATE` a HTTP (`409`, `422`, `400`, `503`) mostrando el mensaje de la regla. | `httperr.Write` en Go + alertas en Alpine.js. |

---

### 3.2 Tabla de trazabilidad `Regla → Mecanismo → Caso de prueba` (Issue #65)

| Código | Regla de Negocio / Integridad | Mecanismo Exacto en la Base de Datos (`001`–`005`) | Caso de Prueba en [`db/tests/db_tests.sql`](../db/tests/db_tests.sql) y [`api_test.go`](../api/internal/httpapi/api_test.go) |
| :--- | :--- | :--- | :--- |
| **RN-01** | El precio de un vino es único para toda la red de salas y siempre mayor que cero. | `vino.precio` + `ck_vino_precio CHECK (precio > 0)` + `uq_vino_nombre_anada_volumen UNIQUE (nombre, anada, volumen_ml)` (`002_constraints.sql:73,77`). | `debe_fallar('RN-01 precio 0')` (`db_tests.sql:135`) · `TestPrecioNegativo` y `TestMensajeVinoDuplicado` (`api_test.go`). |
| **RN-02** | Una sala pertenece a una sola localidad. Cada localidad tiene un único encargado regional. | `sala_venta.id_localidad NOT NULL` + `fk_sala_localidad` + `localidad.cuit_encargado NOT NULL` + `uq_localidad_encargado UNIQUE (cuit_encargado)` (`002_constraints.sql:27`). | `debe_fallar('RN-02 sala con localidad inexistente')` y `debe_fallar('RN-02 mismo encargado en 2 localidades')` (`db_tests.sql:137-138`). |
| **RN-03** | Cada empleado trabaja en una sola sala. | `empleado.id_sala INTEGER NOT NULL` + `fk_empleado_sala REFERENCES sala_venta(id_sala) ON DELETE RESTRICT` (`001_esquema.sql`). | `debe_fallar('RN-03 empleado sin sala')` (`db_tests.sql:140`). |
| **RN-04** | Una parcela tiene una sola cepa y se cosecha como máximo una vez por campaña. | `parcela.id_cepa NOT NULL` + `fk_parcela_cepa` + índice único `idx_lote_uva_parcela_campana ON lote_uva (id_finca, nro_parcela, (EXTRACT(YEAR FROM fecha_cosecha)::INTEGER))` (`002_constraints.sql:60`). | `debe_fallar('RN-04 dos cosechas en 2024')` y `debe_funcionar('RN-04 cosechas en años distintos')` (`db_tests.sql:144,147`). |
| **RN-05** | Los porcentajes de corte de un vino suman exactamente 100. | `ck_composicion_porcentaje` + constraint trigger diferido `trg_composicion_suma_100` (`DEFERRABLE INITIALLY DEFERRED`, `005_triggers.sql:541`). | `debe_fallar('RN-05 composición suma 95')` y `debe_funcionar('RN-05 cambiar corte a 80/20')` (`db_tests.sql:152-153`) · `TestEditarVinoComposicion` (`api_test.go`). |
| **RN-06** | El descuento depende del tipo de cliente: socio 10 %, distribuidor 20 %, exportador 30 %. | `fn_descuento_cliente(id_cliente)` (`003_funciones.sql`) + `trg_cliente_descuento` (`005_triggers.sql:192`) + `ck_cliente_descuento CHECK (descuento BETWEEN 0 AND 35)` (`002_constraints.sql:96`). | `debe_funcionar('RN-06 descuentos 10/20/30')` y `debe_fallar('RN-06 descuento 50 a mano')` (`db_tests.sql:160,162`). |
| **RN-07** | Un exportador puede tener varios permisos; el vencimiento es posterior a la emisión. | `fk_permiso_exportador REFERENCES exportador(id_cliente)` + `ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision)` (`002_constraints.sql:115`). | `debe_fallar('RN-07 vence antes de emitirse')` (`db_tests.sql:167`). |
| **RN-08** | El total del comprobante es la suma de sus renglones con el descuento aplicado. No se carga a mano. | `fn_total_comprobante(nro)` + triggers `trg_comprobante_descuento`, `trg_comprobante_importes`, `trg_comprobante_propaga_descuento`, `trg_renglon_comprobante_bi`, `trg_renglon_comprobante_ai` y `trg_renglon_comprobante_bud` (`005_triggers.sql:84-271`). | 9 casos en `db_tests.sql:169-203` (`total de una venta`, `pisar el total a mano`, `pisar el subtotal a mano`, `U1: cambiar el descuento recalcula el total`, `borrar un renglón suelto`, `cambiar la cantidad de un renglón vendido`, `pisar el subtotal de un renglón`). |
| **RN-09** | No se puede vender más de lo que hay en stock de la sala. El stock nunca es negativo. | `fn_stock_sala(id_sala, cod_vino)` + bloqueo `SELECT ... FOR UPDATE` en `trg_renglon_comprobante_bi` + descuento en `trg_renglon_comprobante_ai` + `ck_stock_sala_cantidad` y `ck_stock_deposito_cantidad` (`002_constraints.sql:156,160`). | `debe_fallar('RN-09 vender 2 con stock 1')`, `debe_funcionar('RN-09 vender todo el stock deja 0')`, `debe_fallar('RN-09 stock negativo a mano')` (`db_tests.sql:214-221`) · `TestVentaSinStock` (`api_test.go`). |
| **RN-10** | Sólo un ingreso terminado impacta en el depósito y pasa a procesado (`en_confeccion → terminado → procesado`). | `ENUM estado_documento` + `trg_ingreso_estado` (`005_triggers.sql:316`) + `sp_terminar_ingreso` y `sp_procesar_ingreso` (`004_procedimientos.sql`). | 7 casos en `db_tests.sql:223-241` (`procesar ingreso en confección`, `procesar ingreso terminado`, `retroceder terminado -> en_confeccion`, `saltar en_confeccion -> procesado`, `crear ingreso ya procesado`, `pasar a procesado sin el procedimiento`). |
| **RN-11** | Igual que RN-10 para transferencias. La fecha de confección es la actual y no se puede modificar. | `trg_transferencia_estado` (`005_triggers.sql:320`) + `trg_transferencia_fecha` (`005_triggers.sql:338`) + `sp_terminar_transferencia` y `sp_procesar_transferencia` (`004_procedimientos.sql`). | 7 casos en `db_tests.sql:233-244` (`procesar sin stock suficiente`, `procesar transferencia OK`, `fecha de confección forzada a hoy`, `modificar fecha de confección`, `sin stock no deja nada a medias`) · `TestCambioEstadoInvalido` (`api_test.go`). |
| **RN-12** | Un ingreso o una transferencia que no está en confección no admite agregar, modificar ni quitar renglones. | `trg_renglon_ingreso_doc` (`005_triggers.sql:379`) y `trg_renglon_transferencia_doc` (`005_triggers.sql:415`). | `debe_fallar('RN-12 agregar renglón a transferencia terminada')`, `debe_fallar('RN-12 borrar renglón de ingreso terminado')`, `debe_funcionar('RN-12 editar renglón en confección')` (`db_tests.sql:248-250`) · `TestQuitarRenglonTransferencia` (`api_test.go`). |
| **RN-13** | Todo cambio de precio de un vino queda auditado (fecha, usuario, precio anterior y nuevo). | Tabla `auditoria_precio` + `trg_vino_auditoria_precio` (`AFTER UPDATE OF precio ON vino`, `005_triggers.sql:435`). | `debe_funcionar('RN-13 cambio de precio auditado')` (`db_tests.sql:253`). |
| **RN-14** | No se puede borrar un transportista, una bodega ni un vino que tengan movimientos asociados. | Claves foráneas con `ON DELETE RESTRICT` (`fk_ingreso_transportista`, `fk_vino_bodega`, `fk_lote_bodega`, `fk_ingreso_bodega`, `fk_rc_vino`, `fk_ri_vino`, `fk_rt_vino`, `fk_stock_sala_vino`, `fk_stock_dep_vino`). | `debe_fallar('RN-14 borrar transportista con ingresos')`, `debe_fallar('RN-14 borrar bodega con vinos')`, `debe_fallar('RN-14 borrar vino con movimientos')` (`db_tests.sql:256-258`) · `TestMensajeBorradoRN14` (`api_test.go`). |
| **RN-15** | Cantidades, superficies, kilos y precios son siempre positivos. La graduación está entre 5 y 20. | `ck_vino_graduacion` (`5..20`), `ck_vino_precio`, `ck_finca_superficie`, `ck_parcela_superficie`, `ck_lote_kg`, `ck_rc_cantidad`, `ck_ri_cantidad`, `ck_rt_cantidad`, `ck_empleado_salario` (`002_constraints.sql`). | `debe_fallar('RN-15 graduación 25')`, `debe_fallar('RN-15 cantidad 0 en renglón')`, `debe_fallar('RN-15 kilos negativos')` (`db_tests.sql:260-262`). |
| **RI-01** | El encargado regional trabaja en una sala de su misma localidad. | FK diferible `fk_localidad_encargado` + constraint triggers diferidos `trg_encargado_localidad`, `trg_encargado_empleado` y `trg_encargado_sala` (`005_triggers.sql:589-599`). | `debe_fallar('RI-01 encargado en sala de otra localidad')` (`db_tests.sql:142`). |
| **RI-02** | Todo vino tiene al menos un maridaje recomendado. | Constraint triggers diferidos `trg_vino_maridaje_obligatorio` y `trg_vino_maridaje_borrado` (`005_triggers.sql:561,566`). | `debe_fallar('RI-02 vino sin maridaje')` (`db_tests.sql:264`). |
| **RI-03** | El precio unitario del renglón es copia histórica de `vino.precio` al momento de la venta. | `trg_renglon_comprobante_bi` copia `vino.precio` en `NEW.precio_unitario` (`005_triggers.sql:84`). | `debe_funcionar('RI-03 copia histórica precio unitario')` (`db_tests.sql:265`). |
| **RI-04** | Los vinos de un ingreso pertenecen a la bodega de origen declarada en el ingreso. | `trg_renglon_ingreso_bodega` (`BEFORE INSERT OR UPDATE ON renglon_ingreso`, `005_triggers.sql:463`). | `debe_fallar('RI-04 vino de otra bodega en el ingreso')` (`db_tests.sql:270`). |
| **RI-05** | El transportista asignado a un ingreso cubre la localidad del depósito central. | `trg_ingreso_transportista` (`BEFORE INSERT OR UPDATE ON ingreso`, `005_triggers.sql:487`). | `debe_fallar('RI-05 transportista que no cubre el depósito')` (`db_tests.sql:271`). |
| **RI-06** | Un exportador con más de 3 permisos recibe un 35 % de descuento. | `fn_descuento_cliente` + `trg_permiso_descuento` (`AFTER INSERT/UPDATE/DELETE ON permiso_exportacion`, `005_triggers.sql:517`). | `debe_funcionar('RI-06 exportador con 4 permisos -> 35')` (`db_tests.sql:163`). |
| **RI-07** | El subtipo coincide con `cliente.tipo` y todo cliente posee su fila en la tabla de subtipo. | `uq_cliente_id_tipo` + FKs compuestas `(id_cliente, tipo)` + `ck_socio_tipo`, `ck_distribuidor_tipo`, `ck_exportador_tipo` + `trg_cliente_subtipo` (`005_triggers.sql:623`). | `debe_fallar('RI-07 subtipo no coincide con supertipo')` (`db_tests.sql:272`). |

---

### 3.3 Modelo de roles y privilegios mínimos

En [`db/migrations/007_roles.sql`](../db/migrations/007_roles.sql) se revocan todos los permisos implícitos de `PUBLIC` (`REVOKE ALL ON SCHEMA public FROM PUBLIC`) y se definen tres roles verificados con [`db/tests/db_tests_roles.sql`](../db/tests/db_tests_roles.sql):
1. **`propietario` (`NOLOGIN`):** dueño de las 31 tablas, 15 secuencias, 4 vistas y todas las funciones/procedimientos.
2. **`app_rw` (`LOGIN`):** rol con el que se conecta la API Go; posee exclusivamente `SELECT, INSERT, UPDATE, DELETE` sobre tablas (con `UPDATE` restringido por columna en `ingreso` y `transferencia` para proteger `estado` y `fecha_confeccion`), `USAGE, SELECT` en secuencias y `EXECUTE` en funciones/procedimientos. No puede alterar estructura ni desactivar triggers.
3. **`reportes_ro` (`LOGIN`):** rol para conexiones de análisis y tableros; posee acceso de solo lectura (`SELECT`) sobre tablas y vistas y `EXECUTE` sobre funciones de consulta, con `REVOKE EXECUTE ON ALL PROCEDURES` para impedir que procese ingresos o transferencias.

---

### 3.4 Demostración de concurrencia (Gestión de la última botella)

Bajo el nivel de aislamiento por defecto de PostgreSQL (`Read Committed`), si dos sesiones intentan vender simultáneamente la última botella de un vino (`stock = 1`) sin bloqueo explícito, ambas leerían `1` antes del `COMMIT` de la otra y producirían una sobreventa.

En [`005_triggers.sql`](../db/migrations/005_triggers.sql), `trg_fn_renglon_comprobante_bi()` adquiere un bloqueo exclusivo de fila antes de verificar el saldo:
```sql
SELECT cantidad INTO v_stock
FROM stock_sala
WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino
FOR UPDATE;
```
- **Sesión A** inserta el renglón por `1` botella y retiene el lock sobre `(id_sala=1, cod_vino=1)`.
- **Sesión B** intenta insertar simultáneamente el renglón por la misma botella y queda bloqueada en el `SELECT ... FOR UPDATE`.
- Cuando **Sesión A** ejecuta `COMMIT`, el stock queda en `0`; **Sesión B** despierta, relee la versión confirmada (`v_stock = 0`) y es abortada inmediatamente con `ERROR: stock insuficiente del vino 1 en la sala 1: hay 0 y se piden 1` (transcripción completa en [`informe_etapa2.md`](entregables/etapa%202/informe_etapa2.md#3-demo-de-concurrencia-gestión-de-la-última-botella)).

---

## 4. Carga masiva de datos

*(Informe completo en [`docs/entregables/etapa 3/informe_etapa3.md`](entregables/etapa%203/informe_etapa3.md) y guía operativa en [`db/seed/README.md`](../db/seed/README.md)).*

- **Volumen total y reproducibilidad:** [`db/seed/seed.py`](../db/seed/seed.py) con `--seed 42` genera **729.551 filas en las 31 tablas** (incluyendo `500.000` en `renglon_comprobante`, `150.000` en `comprobante` y `20.000` en `cliente`), partiendo de 7 catálogos reales en CSV (`departamentos.csv`, `localidades.csv`, `cepas.csv`, `maridajes.csv`, `bodegas.csv`, `transportistas.csv`, `tipos_vino_presentaciones.csv`).
- **Orden topológico en 6 niveles (N1 a N6):** Respeta las 37 claves foráneas y resuelve el ciclo `localidad ↔ empleado ↔ sala_venta` dentro de la misma transacción gracias a que `fk_localidad_encargado` es `DEFERRABLE INITIALLY DEFERRED`.
- **Estrategia frente a los triggers:** Dentro de una única transacción se aplica `ALTER TABLE ... DISABLE TRIGGER USER` (manteniendo activos los triggers internos de `FOREIGN KEY`), se cargan los datos con `COPY ... FROM STDIN`, se sincronizan las 15 secuencias `IDENTITY` con `setval()`, se ejecuta `SET CONSTRAINTS ALL IMMEDIATE` (evitando `SQLSTATE 55006` por eventos diferidos pendientes en `localidad`), se rehabilitan todos los triggers con `ENABLE TRIGGER USER` y se refresca `v_ventas_mensuales_sala`.
- **Comparativa de rendimiento (fila por fila vs. lotes vs. `COPY`):** El benchmark empírico documentado en [`informe_etapa3.md`](entregables/etapa%203/informe_etapa3.md#L127-L137) sobre `10.000` filas de `cliente` registró **4,332 s** (`2.308,5 filas/s`) con `INSERT` fila por fila (`cur.execute`), **0,760 s** (`13.152,6 filas/s`, mejora de **5,70x**) con lotes `cur.executemany` (`batch=1.000`) y **0,067 s** (`148.875,3 filas/s`, mejora de **64,49x** frente a fila por fila y **11,32x** frente a `executemany`) con `COPY ... FROM STDIN`. En la carga completa de las 31 tablas (`729.551` filas), `renglon_comprobante` (`500.000` filas) se inserta con `COPY` en **6,253 s** (`79.961 filas/s`, frente a los `~216 s` que demandaría fila por fila) y el proceso integral finaliza en **10,870 s**.
- **Consultas de control (`C01` a `C14`):** [`db/seed/consultas_control.sql`](../db/seed/consultas_control.sql) verifica conteos, ausencia de huérfanos, sumas de corte = `100`, precios e importes exactos, balance exacto de `stock_deposito` y `stock_sala` y `15/15` secuencias sincronizadas (`0` inconsistencias).

---

## 5. Índices y rendimiento

*(Informe detallado en [`docs/entregables/etapa 4/informe_etapa4.md`](entregables/etapa%204/informe_etapa4.md) y planes completos en [`anexo_planes_baseline.txt`](entregables/etapa%204/anexo_planes_baseline.txt) y [`anexo_planes_con_indices.txt`](entregables/etapa%204/anexo_planes_con_indices.txt)).*

### 5.1 Índices implementados en [`008_indices.sql`](../db/migrations/008_indices.sql)

| Índice | Categoría Exigida | Definición | Consulta Objetivo | Tamaño |
| :--- | :--- | :--- | :---: | ---: |
| `idx_comprobante_sala_fecha` | Compuesto | `comprobante (id_sala, fecha)` | `S3` | 2.040 kB |
| `idx_comprobante_cliente` | Sobre Clave Foránea | `comprobante (id_cliente)` | `D4` | 1.064 kB |
| `idx_transferencia_pendientes` | Parcial (`WHERE`) | `transferencia (id_sala) WHERE estado <> 'procesado'` | `S5` | 16 kB |
| `idx_renglon_transferencia_vino` | Variante `INCLUDE` (Covering) | `renglon_transferencia (cod_vino) INCLUDE (nro, cantidad)` | `S4` | 328 kB |
| `idx_transferencia_fecha` | Simple | `transferencia (fecha_confeccion)` | `S4` | 40 kB |

- **Justificación del orden de columnas en `idx_comprobante_sala_fecha (id_sala, fecha)`:** `S3` filtra `id_sala = $1` por igualdad y `fecha >= CURRENT_DATE - INTERVAL '7 days'` por rango. Ubicar primero la columna de igualdad permite acotar el subárbol B-Tree a una sola sala y recorrer únicamente su tramo final de fechas.

### 5.2 Tabla comparativa de planes y tiempos (`EXPLAIN (ANALYZE, BUFFERS)`)

| Consulta | Mediana Antes | Mediana Después | Mejora | Plan Antes → Plan Después | Filas Leídas (Antes → Después) | Buffers (Antes → Después) |
| :--- | ---: | ---: | ---: | :--- | :--- | :--- |
| **S3** | 9,2 ms | **5,7 ms** | **-37 %** | `Parallel Seq Scan` → `Bitmap Index Scan` (`idx_comprobante_sala_fecha`) | 150.000 → 835 | 2.938 → 1.237 |
| **S4** | 1,1 ms | **0,6 ms** | **-44 %** | `Seq Scan` → `Index Only Scan` (`idx_renglon_transferencia_vino`) + `Bitmap Index Scan` | 10.000/2.500 → 327/186 | 69 → 21 |
| **S5** | 0,4 ms | **0,3 ms** | **-22 %** | `Seq Scan` → `Bitmap Index Scan` (`idx_transferencia_pendientes`) | 2.500 → 150 | 15 → 4 |
| **D4** | 112,2 ms | **10,9 ms** | **-90 %** | `Seq Scan + Hash Anti Join` → `Index Only Scan + Nested Loop Anti Join` (`idx_comprobante_cliente`) | 150.000 → 1 búsqueda por socio | 1.535 → 7.236 |

- **Costo de escritura ([`informe_etapa4.md`](entregables/etapa%204/informe_etapa4.md#L103-L115)):** Al medir el impacto de los 5 índices nuevos (`3.488 kB` en total) durante `COPY` masivo, `comprobante` (`150.000` filas, 2 índices nuevos) pasa de `1,368 s` a `1,611 s` (`+0,243 s`, `+18 %`), `renglon_transferencia` (`10.000` filas, 1 índice `INCLUDE`) de `0,083 s` a `0,093 s` (`+12 %`), `transferencia` (`2.500` filas, 2 índices nuevos) de `0,015 s` a `0,018 s` (`+20 %`), y la carga completa de las `729.551` filas pasa de `7,25 s` a `7,50 s` (`+0,25 s`, **`+3 %`**), sobrecosto marginal frente a la reducción del `90 %` en `D4` y `37 %` en `S3`.
- **Caso donde el planificador no usa el índice ([`caso_sin_uso_indice.sql`](entregables/etapa%204/caso_sin_uso_indice.sql)):** Al filtrar `comprobante` con un predicado de **baja selectividad** sobre la columna indexada (`WHERE id_sala BETWEEN 1 AND 30`, que devuelve `125.004` de las `150.000` filas = **`83 %`** de la tabla), el optimizador descarta `idx_comprobante_sala_fecha` y elige `Parallel Seq Scan` en **`54,0 ms`** (Caso A). Si se fuerza el uso del índice con `SET enable_seqscan = off` (Caso B), el `Bitmap Index Scan` tarda **`94,3 ms`** (`+75 %` más lento y lee `343` bloques adicionales del índice). En cambio, cuando el predicado es selectivo (`WHERE id_sala = 12`, `4.167` filas = **`2,8 %`**, Caso C), el planificador elige espontáneamente `Bitmap Index Scan` y resuelve en **`4,4 ms`**.

---

## 6. Consultas SQL

Las 30 consignas de la Sección 8 se encuentran resueltas, comentadas y probadas en transacción dentro de la carpeta [`consultas/`](../consultas/):

1. **Modificaciones — [`consultas/update.sql`](../consultas/update.sql) (`U1` a `U6`):**
   - `U1`: Prepara el caso insertando un 4.º permiso (`'PRUEBA-U1'`) a un exportador que tenía 3 permisos (subiendo su descuento a `35 %`, `RI-06`) y recalcula en `comprobante` el `porcentaje_descuento = fn_descuento_cliente(id_cliente)` (`WHERE porcentaje_descuento <> fn_descuento_cliente(id_cliente)`), disparando `trg_comprobante_importes` (recalcula `total` vía `fn_total_comprobante()`) y `trg_comprobante_propaga_descuento` hacia los renglones.
   - `U2`: Incrementa un `20 %` el salario de empleados con `fn_antiguedad_anios(fecha_ingreso) > 5`.
   - `U3` y `U5`: Modifican `vino.precio` (+13 % a una bodega recibida por `-v bodega=...`; -15 % a los 10 vinos menos vendidos que están presentes en salas de venta tomando `SELECT DISTINCT cod_vino FROM stock_sala` + `LEFT JOIN renglon_comprobante` para incluir los de `0` ventas sin mezclar los `152` vinos que nunca llegaron a salas), disparando automáticamente `trg_vino_auditoria_precio` (`RN-13`) sin alterar el `precio_unitario` histórico de ventas pasadas (`RI-03`).
   - `U4`: Intercambia `lunes ↔ miércoles` en `sala_venta.dia_cierre` en una sola sentencia con `CASE`.
   - `U6`: Actualiza a `35 %` el descuento de exportadores con más de 3 permisos (`RI-06`); dado que el seed ya los mantiene en `35 %` por `trg_permiso_descuento`, el bloque reduce previamente a `30 %` el descuento de un exportador con >3 permisos y acota el `UPDATE` con `WHERE descuento <> 35` para que `trg_cliente_subtipo` se evalúe solo sobre las filas efectivamente modificadas.
2. **Inserciones — [`consultas/insert.sql`](../consultas/insert.sql) (`I1` a `I6`):**
   - `I1`: Registra cobertura en `'General Alvear'` para el transportista con menos envíos en el último trimestre (`LEFT JOIN ingreso` con fecha en el `ON` + `NOT EXISTS`).
   - `I2`: Usa un CTE modificador (`WITH nuevo_maridaje AS (INSERT INTO maridaje ... WHERE EXISTS (...) RETURNING id_maridaje)`) para crear «cordero al disco» y asociarlo en una sola sentencia a los `81` vinos tintos con graduación $\ge 14^\circ$.
   - `I3`: Crea una venta completa en la sala `1` insertando solo `(id_cliente, id_sala)` en `comprobante` y `(nro, cod_vino, cantidad)` en `renglon_comprobante`, dejando que `trg_comprobante_descuento`, `trg_renglon_comprobante_bi` y `trg_renglon_comprobante_ai` completen precios, descuentos, subtotales, stock (`fn_stock_sala`) y total (`fn_total_comprobante`).
   - `I4`, `I5`, `I6`: Alta de bodega (`DOMAIN cuit`), sala de venta (`ENUM dia_semana`, `RI-01` evaluada con `SET CONSTRAINTS ALL IMMEDIATE`) e ingreso en confección de 120 botellas mediante CTE modificador (`trg_ingreso_transportista`, `trg_ingreso_estado`, `trg_renglon_ingreso_doc`, `trg_renglon_ingreso_bodega`).
3. **Borrados — [`consultas/delete.sql`](../consultas/delete.sql) (`D1` a `D6`):**
   - Documenta el arrastre automático por `ON DELETE CASCADE` (renglones en `D1` y `D5`; subtipo `socio` en `D4` y `D6`) y la eliminación limpia de las 3 cepas sin uso en `D2` frente a `ON DELETE RESTRICT`.
4. **Consultas Básicas y Avanzadas — [`consultas/select.sql`](../consultas/select.sql) (`S1` a `S12`):**
   - `S2` y `S12a`: **División relacional** implementada mediante doble negación con `NOT EXISTS (...)` (vinos vendidos en todas las salas y clientes que compraron todos los vinos de una bodega).
   - `S9`: Ficha integral de un vino combinando agregación `STRING_AGG` de cepas y maridajes con la vista [`v_stock_total_vino`](../db/migrations/006_vistas.sql).
   - `S10`: CTE `rendimiento` (`kg / superficie_ha` por parcela y campaña) combinado con subconsulta correlacionada para detectar parcelas que rinden por debajo del promedio de su finca.
   - `S11`: Funciones de ventana `RANK() OVER (PARTITION BY id_sala ORDER BY botellas_vendidas DESC)` y acumulado mensual `SUM(ventas_mes) OVER (PARTITION BY id_sala ORDER BY mes)`.

---

## 7. API REST y Frontend

*(Documentación técnica en [`api/docs/api.md`](../api/docs/api.md), OpenAPI en [`api/docs/openapi.yaml`](../api/docs/openapi.yaml) y anexo de seguridad en [`docs/entregables/etapa 6/anexo_inyeccion_sql.md`](entregables/etapa%206/anexo_inyeccion_sql.md)).*

### 7.1 Arquitectura de la API Go (`chi` + `pgxpool`)
- **Separación estricta de responsabilidades:**
  - `api/internal/config`: lectura de `DATABASE_URL` y `PORT` desde variables de entorno.
  - `api/internal/db`: capa de acceso a datos con una función por consulta (`vinos.go`, `clientes.go`, `comprobantes.go`, `transferencias.go`, `ingresos.go`, `reportes.go`), **100 % parametrizadas (`$1`, `$2`, ...)** y con manejo explícito de transacciones (`Pool.Begin` / `Commit` / `Rollback`).
  - `api/internal/httpapi`: controladores HTTP REST que exponen los CRUDs, el simulador de ventas (`POST /comprobantes/simular` con `ROLLBACK` deliberado), los circuitos de ingresos/transferencias y los reportes `S1`–`S12`.
  - `api/internal/httperr`: traductor central de errores de PostgreSQL (`pgconn.PgError`) a respuestas HTTP con mensajes legibles en castellano (`mensajes.go`):
    - `23505` (`UNIQUE`) y `23503` (`FOREIGN KEY`) $\rightarrow$ `409 Conflict`
    - `23514` (`CHECK`) y `23502` (`NOT NULL`) $\rightarrow$ `422 Unprocessable Entity`
    - `P0001` (`RAISE EXCEPTION` de triggers/procedimientos RN/RI) $\rightarrow$ `409 Conflict`
    - `22P02` (formato inválido) $\rightarrow$ `400 Bad Request`
    - `40001` / `40P01` (fallo de serialización / deadlock) $\rightarrow$ `503 Service Unavailable`

### 7.2 Demostración de Inyección SQL Fallida
En [`api_test.go`](../api/internal/httpapi/api_test.go) (`TestInyeccionSQL`) y [`anexo_inyeccion_sql.md`](entregables/etapa%206/anexo_inyeccion_sql.md) se envía el payload malicioso `tipo='; DROP TABLE vino; --` a `GET /vinos`. El log de PostgreSQL (`log_statement = all`) evidencia que `pgx` lo envía como parámetro ligado separado de la sentencia:
```text
LOG:  execute stmtcache_2c87…: SELECT … FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega
        WHERE v.tipo::text = $1 ORDER BY v.cod_vino LIMIT $2 OFFSET $3
DETAIL:  parameters: $1 = '''; DROP TABLE vino; --', $2 = '20', $3 = '0'
```
La consulta devuelve `HTTP 200` con `{"total":0,"vinos":[]}` y las `400` filas de `vino` permanecen intactas.

### 7.3 Frontend en Alpine.js (`front/`)
La interfaz web implementa las **5 pantallas exigidas** (`Catálogo de vinos`, `Alta y edición de vino`, `Nueva venta`, `Transferencias` y `Tablero`) consumiendo únicamente la API a través de [`front/js/api.js`](../front/js/api.js). No realiza ningún cálculo de importes ni de stock en JavaScript y muestra debajo de cada alerta el mensaje exacto de la regla devuelto por la base de datos junto con su código `SQLSTATE` y nombre de restricción.

---

## 8. Despliegue en la nube

*(Informe extendido de la Etapa 8 en [`docs/entregables/etapa 8/informe_etapa8_nube.md`](entregables/etapa%208/informe_etapa8_nube.md)).*

### 8.1 Elección de Proveedor y Límites del Plan (Issue #57)
Tras comparar **Neon + Render**, **Supabase + Fly.io/Railway**, **VPS con Docker Compose** y **Render Managed Postgres**, se seleccionó **Neon Serverless PostgreSQL 16 + Render (Web Service en Go + Static Site con Rewrite Proxy)**:
- **Ventajas decisivas:** No requiere tarjeta de crédito, no elimina la base a los 30 días (como ocurre en Render Postgres Free) ni pausa el proyecto exigiendo reactivación manual a los 7 días (como Supabase Free).
- **Límites y dimensionamiento:** El plan gratuito de Neon ofrece **512 MB** de almacenamiento por proyecto y **190 h/mes** de cómputo activo con *auto-suspend*. El dataset completo de `seed.py --seed 42` (`729.551` filas + índices) ocupa **~125 MB**, por lo que cabe íntegramente dentro del plan gratuito sin necesidad de recortar el volumen.

### 8.2 Seguridad, Backup y Restauración
1. **Cifrado en tránsito y red:** El Frontend y la API se publican bajo **HTTPS (TLS 1.3)** y la API se conecta a PostgreSQL exigiendo **`sslmode=require`**. En despliegues sobre VPS con Docker Compose, el contenedor `db` permanece aislado en la red bridge interna sin publicar el puerto `5432` a Internet.
2. **Privilegios mínimos y secretos:** La API opera en la nube con el rol `app_rw` y recibe `DATABASE_URL` mediante variables de entorno secretas del proveedor (jamás en Git).
3. **Backup y restauración verificados:** Se genera el resguardo con `pg_dump --format=custom --no-owner --no-privileges`, se restaura con `pg_restore` sobre una base limpia (`atuel_restore`) y se ejecutan los 14 controles de `db/seed/consultas_control.sql` comprobando coincidencia exacta de conteos e invariantes.

---

## 9. Conclusiones

1. **Dificultades técnicas superadas:**
   - **Ciclo referencial `localidad ↔ empleado ↔ sala_venta`:** Exigir que toda localidad tenga un encargado (`RN-02`) y que todo empleado trabaje en una sala de esa localidad (`RN-03`, `RI-01`) genera un ciclo circular al insertar datos o cargar el seed. Resolverlo mediante `fk_localidad_encargado DEFERRABLE INITIALLY DEFERRED` y los constraint triggers diferidos `trg_encargado_*` permitió mantener las columnas `NOT NULL` sin sacrificar integridad.
   - **Carga masiva frente a triggers diferidos ($O(N^2)$):** Desactivar temporalmente solo los triggers de usuario (`DISABLE TRIGGER USER`) dentro de una transacción, validar por construcción los saldos diarios con aritmética `Decimal` exacta y ejecutar `SET CONSTRAINTS ALL IMMEDIATE` antes de `ENABLE TRIGGER USER` permitió cargar `729.551` filas en ~11 segundos sin perder la verificación de las 37 `FOREIGN KEY`.
   - **Selectividad y paralelismo en el optimizador de PostgreSQL:** Las pruebas con `EXPLAIN (ANALYZE, BUFFERS)` demostraron que un índice no siempre acelera una consulta: en `S8` (donde el filtro conserva el `28 %` de la tabla) un `Parallel Seq Scan` con 2 workers supera en tiempo a un `Index Only Scan` monohilo, mientras que en predicados selectivos (`S3`, `S4`, `S5`, `D4`) los índices compuestos, parciales, `INCLUDE` y de FK redujeron los tiempos entre un `22 %` y un `90 %`.
2. **Decisiones que demostraron su valor:**
   - Centralizar los cálculos y validaciones en PostgreSQL simplificó drásticamente la API Go y el Frontend Alpine.js: el endpoint `POST /comprobantes/simular` reutiliza exactamente los mismos triggers que la venta real simplemente cerrando la transacción con `ROLLBACK`, garantizando que el total previsualizado en pantalla coincida al centavo con el comprobante emitido.
