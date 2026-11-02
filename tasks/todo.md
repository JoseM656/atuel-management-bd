# Task List — Bodegas del Atuel

Checklist operativa del proyecto. Cada sección es un milestone (etapa) con su descripción, y cada item es un issue/tarea con **Descripción**, **Aceptación**, **Verificación** y **Archivos**. Nombres de tablas, reglas (RN/RI), consultas (U/I/D/S), endpoints y funciones corresponden a `SPEC.md` y `docs/consignas.md`.

---

## Milestone 1 — Etapa 1: Modelado ✓ (COMPLETA)

> La etapa 1 se centra en la documentación inicial: pasar del escenario escrito a un esquema físico en PostgreSQL, recorriendo el DER, el esquema relacional, la normalización 3FN, el diccionario de datos y el DDL base.

- [x] **DER completo**
  - Descripción: modelo entidad-relación con notación consistente. Se subrayan del escenario las entidades, atributos, relaciones y cardinalidades, y se marcan las reglas que requieren lógica adicional. Deben quedar explícitas las 23 entidades, las 27 relaciones, las cardinalidades mín/máx, la entidad débil `parcela`, la jerarquía de `cliente` y las relaciones N:M con atributos (`composicion`, `renglon_comprobante`, `renglon_ingreso`, `renglon_transferencia`, `stock_sala`, `transportista_localidad`, `vino_maridaje`).
  - Aceptación: todas las entidades de la sección 5 representadas; cardinalidades coherentes con el escenario; notación uniforme.
  - Verificación: `docs/entregables/etapa 1/DER.png`.
  - Archivos: `docs/entregables/etapa 1/DER.png`.

- [x] **Esquema relacional**
  - Descripción: transformar el DER en 31 relaciones aplicando las reglas de mapeo (una tabla por entidad y por relación N:M; entidad débil con PK compuesta; relación 1:1 con FK+UNIQUE; jerarquía supertipo+subtipos). Se documentan las 37 claves foráneas y sus acciones referenciales, y se justifica el ciclo `localidad → empleado → sala_venta → localidad` resuelto con la FK del encargado DEFERRABLE.
  - Aceptación: 31 relaciones listadas con PK/FK; mapeo de la jerarquía justificado; 37 FK documentadas con ON DELETE/ON UPDATE.
  - Verificación: `docs/entregables/etapa 1/esquema_relacional_escrito.md`.
  - Archivos: `docs/entregables/etapa 1/esquema_relacional_escrito.md`.

- [x] **Normalización 3FN**
  - Descripción: listar las dependencias funcionales relevantes (p. ej. `localidad → encargado regional`, `departamento → provincia`) y demostrar que no quedan dependencias parciales ni transitivas. Se explica por qué `departamento` va en tabla propia (elimina la transitiva en `finca`) y por qué `campaña` no es columna (se deriva del año de `fecha_cosecha`).
  - Aceptación: esquema en 3FN con justificación escrita, sin excepciones.
  - Verificación: `esquema_relacional_escrito.md` y `desiciones_diseño.md`.
  - Archivos: `docs/entregables/etapa 1/esquema_relacional_escrito.md`.

- [x] **Decisiones de diseño**
  - Descripción: resolver y justificar las 5 decisiones exigidas — jerarquía de clientes (supertipo + tabla por subtipo, para evitar NULL y permitir FK simple en `comprobante` y `permiso_exportacion`), claves naturales vs subrogadas (CUIT natural en bodega/empleado, IDENTITY en el resto), tipos de datos (`NUMERIC`, `DATE`/`TIMESTAMPTZ`, ENUM, DOMAIN `cuit`), atributos derivados (cuáles se guardan y cuáles se calculan) y acciones referenciales (CASCADE solo en dependientes, RESTRICT en movimientos).
  - Aceptación: las 5 decisiones resueltas con ventajas/desventajas y elección justificada.
  - Verificación: `docs/entregables/etapa 1/desiciones_diseño.md`.
  - Archivos: `docs/entregables/etapa 1/desiciones_diseño.md`.

- [x] **Diccionario de datos**
  - Descripción: para cada tabla y columna indicar tipo, si admite nulos, restricciones y descripción. Incluye la definición de los 5 ENUM (`estado_documento`, `tipo_cliente`, `tipo_vino`, `tipo_cepa`, `dia_semana`) y el DOMAIN `cuit`.
  - Aceptación: coincide con el esquema físico; ningún importe usa FLOAT; estados no son texto libre.
  - Verificación: `docs/entregables/etapa 1/diccionario_datos.md`.
  - Archivos: `docs/entregables/etapa 1/diccionario_datos.md`.

- [x] **001_esquema.sql**
  - Descripción: DDL base con tipos propios (ENUM + DOMAIN `cuit`), las 31 tablas, columnas con NOT NULL, claves primarias y foráneas con sus acciones referenciales. La FK `localidad.cuit_encargado` se agrega al final como DEFERRABLE INITIALLY DEFERRED para romper el ciclo de dependencias. Las UNIQUE/CHECK/DEFAULT adicionales quedan para la etapa 2 (`002_constraints.sql`).
  - Aceptación: corre de punta a punta sobre una base vacía, en una transacción, sin errores.
  - Verificación: `psql -f db/migrations/001_esquema.sql`.
  - Archivos: `db/migrations/001_esquema.sql`.

---

## Milestone 2 — Etapa 2: Integridad y lógica

> Etapa de mayor peso: que las reglas de negocio (RN-01…15 y RI-01…07) vivan dentro de la base mediante constraints, funciones, procedimientos, triggers, vistas y roles, con pruebas y una demo de concurrencia.

- [x] **002_constraints.sql**
  - Descripción: completar UNIQUE, CHECK y DEFAULT sobre el DDL de 001. Casos concretos: `vino` con UNIQUE(nombre, anada, volumen_ml) y CHECK de graduación 5–20, precio>0 y volumen en {187,375,750,1500,3000}; `lote_uva` con índice único de expresión (parcela, año de cosecha) para RN-04; CUIT UNIQUE en `bodega` y `transportista`; `permiso_exportacion` con CHECK vencimiento>emisión (RN-07); `stock_sala`/`stock_deposito` con CHECK cantidad>=0; DEFAULT de estado `en_confeccion` y de fechas de alta actuales.
  - Aceptación: 4 UNIQUE adicionales, 8 CHECK (al menos uno entre columnas), 3 DEFAULT; acciones referenciales consistentes (CASCADE en dependientes, RESTRICT en movimientos, ON UPDATE CASCADE solo en CUIT).
  - Verificación: `psql -f db/migrations/002_constraints.sql` sobre 001 sin errores.
  - Archivos: `db/migrations/002_constraints.sql`.

- [x] **003_funciones.sql**
  - Descripción: implementar `fn_total_comprobante` (total con descuento), `fn_stock_sala` (stock de un vino en una sala), `fn_descuento_cliente` (10/20/30 % según tipo; 35 % para exportador con >3 permisos, RN-06/RI-06) y `fn_antiguedad_anios`. Cada una con comentario de cabecera indicando propósito, parámetros y volatilidad (STABLE/IMMUTABLE).
  - Aceptación: 4 funciones operativas y usadas por los triggers/procedimientos de esta etapa.
  - Verificación: `psql -f db/migrations/003_funciones.sql` + SELECT de prueba por función.
  - Archivos: `db/migrations/003_funciones.sql`.

- [x] **004_procedimientos.sql**
  - Descripción: `sp_procesar_ingreso` y `sp_procesar_transferencia` transaccionales: validan el estado, bloquean las filas necesarias con `FOR UPDATE`, actualizan `stock_deposito`/`stock_sala` y cambian el estado; si algo falla, todo se revierte. Cubrir el caso límite del Anexo A.6: un vino del renglón sin fila en `stock_deposito` no debe pasar en silencio (verificar existencia y suficiencia antes de descontar).
  - Aceptación: solo un documento `terminado` se procesa y pasa a `procesado`; procesar sin stock suficiente no deja cambios a medias.
  - Verificación: `psql -f db/migrations/004_procedimientos.sql` + `CALL sp_procesar_transferencia(nro)` con stock insuficiente.
  - Archivos: `db/migrations/004_procedimientos.sql`.

- [x] **005_triggers.sql**
  - Descripción: triggers que protegen RN-09 (validación de stock en venta, BEFORE INSERT en `renglon_comprobante`), RN-08 (descuento de stock y cálculo de totales, AFTER INSERT en `renglon_comprobante`), RN-10/RN-11 (control de estados ingreso/transferencia sin retroceso), RN-12 (bloqueo de renglones si el documento no está en confección), RN-11 (fecha de confección inmutable), RN-13 (auditoría de precio, AFTER UPDATE en `vino`), RN-05 (suma de cortes = 100, constraint trigger DEFERRABLE INITIALLY DEFERRED) y las implícitas RI-01…RI-07. Cada uno encabezado con comentario que cita la regla.
  - Aceptación: al menos un BEFORE, un AFTER y un constraint trigger diferido; RI-01…RI-07 cubiertas; cada regla RN señalable a su trigger.
  - Verificación: `psql -f db/migrations/005_triggers.sql`; disparar venta sin stock y edición de un documento no confección.
  - Archivos: `db/migrations/005_triggers.sql`.

- [x] **006_vistas.sql**
  - Descripción: 3 vistas — stock total por vino (depósito + salas, para el tablero y S6/S9), ventas mensuales por sala (para S8/S11) y documentos pendientes (ingresos/transferencias no procesados, para S5). Una puede ser materializada; la vista de clientes (para resolver los joins del supertipo+subtipos) también encaja acá.
  - Aceptación: las 3 vistas consultables y coherentes con las tablas base.
  - Verificación: `psql -f db/migrations/006_vistas.sql` + SELECT por vista.
  - Archivos: `db/migrations/006_vistas.sql`.

- [x] **007_roles.sql**
  - Descripción: 3 roles — propietario, `app_rw` (lectura/escritura para la API) y un rol de solo lectura para reportes. Se hace `REVOKE ALL ON SCHEMA public FROM PUBLIC` y se otorgan privilegios mínimos (USAGE en schema, DML en tablas, EXECUTE en rutinas). La contraseña de `app_rw` se pasa por variable de entorno, nunca en el repo.
  - Aceptación: la API se conecta con `app_rw` sin privilegios de propietario; el rol de reportes solo puede SELECT.
  - Verificación: `psql -f db/migrations/007_roles.sql`; probar conexión como `app_rw`.
  - Archivos: `db/migrations/007_roles.sql`.

- [x] **db_tests.sql**
  - Descripción: script de pruebas SQL con casos que deben funcionar y casos que deben fallar. Al menos un caso por RN-01…RN-15 y RI-01…RI-07; cada caso que debe fallar comenta el error esperado. Sirve para demostrar que las reglas se cumplen sin importar quién acceda a la base.
  - Aceptación: los casos que deben fallar fallan con mensaje claro; los que deben funcionar, funcionan; cobertura completa de RN+RI.
  - Verificación: `psql -f db/tests/db_tests.sql`.
  - Archivos: `db/tests/db_tests.sql`.

- [x] **Demo de concurrencia**
  - Descripción: dos sesiones `psql` intentan vender la última botella de un vino. Mostrar el comportamiento con y sin `SELECT … FOR UPDATE`, y explicar por qué según el nivel de aislamiento ambas sesiones podrían vender la misma botella sin el bloqueo. Queda en el informe con capturas.
  - Aceptación: con FOR UPDATE una sesión espera, la segunda ve stock 0 y rechaza; sin FOR UPDATE ambas pueden vender la misma botella.
  - Verificación: capturas en el informe de la etapa 2.
  - Archivos: `docs/` (informe etapa 2).

---

## Milestone 3 — Etapa 3: Carga masiva ✓ (COMPLETA)

> Generar datos coherentes y reproducibles a gran escala (≥100k filas en una tabla) con Python + Faker + semilla fija, catálogos reales en CSV y consultas de control.

- [x] **Catálogos CSV**
  - Descripción: catálogos reales del Anexo B — cepas tintas (Malbec, Cabernet Sauvignon, Merlot, Syrah, Bonarda, Tempranillo, Pinot Noir) y blancas (Chardonnay, Sauvignon Blanc, Torrontés, Chenin Blanc, Semillón), maridajes con temperatura de servicio, departamentos de Mendoza, tipos de vino y presentaciones (187/375/750/1500/3000 ml). Estos datos no se generan al azar.
  - Aceptación: catálogos completos (10–60 filas cada uno) listos para el script de carga.
  - Verificación: archivos en `db/seed/`.
  - Archivos: `db/seed/*.csv`.

- [x] **Script de carga Python**
  - Descripción: `psycopg` + `Faker` + `random` con semilla fija, respetando el orden de carga por dependencias FK (primero las tablas sin dependencias, después las que referencian). El orden se dibuja en el informe. Datos coherentes: cosecha antes de elaboración, ingreso antes de venta, cortes que suman 100, descuentos por tipo, stocks no negativos.
  - Aceptación: reproducible — dos ejecuciones con la misma semilla producen los mismos datos.
  - Verificación: `python db/seed/seed.py` dos veces → mismos conteos.
  - Archivos: `db/seed/seed.py`, `db/seed/README.md`.

- [x] **Coherencia y triggers en carga**
  - Descripción: asegurar coherencia temporal y numérica de los datos generados, y resolver la carga histórica frente a los triggers: deshabilitarlos durante la carga con `ALTER TABLE … DISABLE TRIGGER`, volver a habilitarlos y validar con consultas de control. Documentar la decisión y sus riesgos.
  - Aceptación: estrategia ante triggers documentada; datos finales coherentes sin inconsistencias.
  - Verificación: reporte etapa 3 + consultas de control.
  - Archivos: `db/seed/`, `docs/` (reporte).

- [x] **Carga eficiente por lotes**
  - Descripción: inserción por lotes (`execute_values`/`executemany` o `COPY`) y medición del tiempo fila a fila vs por lotes. Cumplir los mínimos de volumen: todas las tablas con ≥1 fila, ≥3 tablas >10 000, ≥1 tabla >100 000 (renglones de comprobante → 500 000).
  - Aceptación: ≥100 000 filas en una tabla; renglones de comprobante ~500 000; tiempos registrados.
  - Verificación: reporte de tiempos y conteos.
  - Archivos: `db/seed/`, `docs/` (reporte).

- [x] **Consultas de control y dump**
  - Descripción: consultas de control — conteo por tabla, filas huérfanas, stock negativo, comprobantes cuyo total no coincide con la suma de sus renglones — y volcado de la base cargada con `pg_dump` (`dump_completo.sql.gz`) para poder restaurarla.
  - Aceptación: sin inconsistencias; dump generado (o instrucciones si supera el tamaño permitido).
  - Verificación: `pg_dump` + consultas de control con resultados en el reporte.
  - Archivos: `db/seed/`, `dump_completo.sql.gz`.

---

## Milestone 4 — Etapa 4: Índices

> Diseñar índices con evidencia medida (`EXPLAIN ANALYZE, BUFFERS`), comparando antes/después y documentando el costo de escritura.

- [ ] **Medición baseline**
  - Descripción: ejecutar `ANALYZE` y medir ≥3 consultas candidatas de la sección 8 (S1, S4, S8, S10) con `EXPLAIN (ANALYZE, BUFFERS)` usando solo los índices de PK/UNIQUE. Guardar plan y tiempo de cada una antes de crear índices.
  - Aceptación: plan y tiempo baseline guardados.
  - Verificación: informe etapa 4.
  - Archivos: `docs/` (informe).

- [ ] **008_indices.sql**
  - Descripción: crear ≥5 índices a partir de lo que muestran los planes (recorridos secuenciales, ordenamientos costosos, joins sin índice). Deben incluir uno compuesto (justificar orden de columnas), uno parcial (`WHERE`), uno sobre una clave foránea (PostgreSQL no indexa FK automáticamente) y una variante (de expresión, BRIN o `INCLUDE`).
  - Aceptación: los 5+ índices creados y justificados.
  - Verificación: `psql -f db/migrations/008_indices.sql`.
  - Archivos: `db/migrations/008_indices.sql`.

- [ ] **Comparativa y costo de escritura**
  - Descripción: repetir `ANALYZE` y las mediciones, armar tabla comparativa (tiempo antes/después, tipo de scan: Seq/Index/Bitmap, filas leídas), justificar un índice evaluado y descartado, medir el costo de escritura de una tabla grande con y sin índices, y mostrar un caso donde el planificador no usa un índice (baja selectividad / estadísticas desactualizadas).
  - Aceptación: mejora medida en ≥3 consultas; costo de escritura y caso de no-uso documentados.
  - Verificación: informe etapa 4.
  - Archivos: `docs/` (informe).

---

## Milestone 5 — Etapa 5: Consultas SQL

> Resolver en SQL las operaciones de inserción, modificación, borrado y consulta (U1–U6, I1–I6, D1–D6, S1–S12), probadas en transacción sobre la base cargada.

- [ ] **consultas/update.sql**
  - Descripción: U1 (recalcular el total de todos los comprobantes con `fn_descuento_cliente`), U2 (+20 % salario a empleados con >5 años de antigüedad), U3 (+13 % precio a vinos de una bodega determinada), U4 (cambiar lunes↔miércoles en una sola sentencia), U5 (−15 % a los 10 vinos menos vendidos de la red), U6 (exportadores con >3 permisos → 35 %). Cada una con encabezado (código, enunciado, estrategia) y probada en transacción.
  - Aceptación: U1–U6 comentadas, con estrategia y probadas con control previo/posterior + ROLLBACK.
  - Verificación: `psql -f consultas/update.sql`.
  - Archivos: `consultas/update.sql`.

- [ ] **consultas/insert.sql**
  - Descripción: I1 (cobertura General Alvear con el transportista con menos ingresos en el trimestre), I2 (crear «cordero al disco» si existe tinto ≥14° y asociarlo), I3 (comprobante de 3 renglones en sala 1 usando funciones de cálculo), I4 (nueva bodega), I5 (nueva sala), I6 (ingreso en confección de 120 botellas de un vino dado).
  - Aceptación: I1–I6 comentadas, probadas en transacción, usando las funciones de cálculo (no valores a mano).
  - Verificación: `psql -f consultas/insert.sql`.
  - Archivos: `consultas/insert.sql`.

- [ ] **consultas/delete.sql**
  - Descripción: D1 (comprobantes >5 años de socios), D2 (cepas sin composición ni parcela), D3 (empleados de una sala dada de baja con <2 años), D4 (socios sin compras y alta >5 años), D5 (ingresos procesados >365 días), D6 (socios sin compras de una localidad). Anotar qué triggers/constraints se disparan (p. ej. CASCADE en renglones, RESTRICT en movimientos).
  - Aceptación: D1–D6 comentadas, probadas en transacción; documentados los efectos colaterales.
  - Verificación: `psql -f consultas/delete.sql`.
  - Archivos: `consultas/delete.sql`.

- [ ] **consultas/select.sql**
  - Descripción: S1 (top 10 vinos), S2 (división relacional: vendidos en todas las salas), S3 (clientes por tipo en la última semana), S4 (top 5 salas por transferencias de un vino en 15 días), S5 (salas con menos pendientes), S6 (vinos sin stock en sala pero con stock en depósito), S7 (transportista más activo del mes), S8 (ventas por sala del trimestre) y las avanzadas S9 (ficha de vino con joins/vista), S10 (kg/ha con CTE y subconsulta correlacionada), S11 (`RANK() OVER (PARTITION BY …)` + acumulado), S12 (`NOT EXISTS`/anti-join). "Última semana/trimestre" se calcula desde `CURRENT_DATE`.
  - Aceptación: S1–S12 resueltas, comentadas y con `EXPLAIN (ANALYZE)` en S9–S12.
  - Verificación: `psql -f consultas/select.sql`.
  - Archivos: `consultas/select.sql`.

---

## Milestone 6 — Etapa 6: API REST

> Exponer la base mediante una API en Go (chi + pgx) sin ocultar el SQL, con capa de acceso a datos, traducción de errores SQLSTATE→HTTP y pruebas automáticas.

- [ ] **Estructura del proyecto Go**
  - Descripción: `api/` con `go.mod`, router `chi` y paquetes separados por responsabilidad: `internal/config` (variables de entorno), `internal/db` (acceso a datos), `internal/httpapi` (handlers), `internal/httperr` (errores). La regla de oro aplica desde el inicio: la API no recalcula totales, descuentos ni stock.
  - Aceptación: compila; estructura por responsabilidad.
  - Verificación: `go build ./...`.
  - Archivos: `api/go.mod`, `api/cmd/api/main.go`, `api/internal/config/`.

- [ ] **Conexión y /salud**
  - Descripción: pool `pgx` (`pgxpool`) leyendo `DATABASE_URL` desde variables de entorno, conectando con el rol `app_rw`. Endpoint `GET /salud` que verifica que la API llega a la base.
  - Aceptación: `/salud` responde 200 con base accesible; credenciales fuera del código.
  - Verificación: `go run ./cmd/api` + `curl /salud`.
  - Archivos: `api/internal/db/`, `api/internal/httpapi/`.

- [ ] **Capa de acceso a datos**
  - Descripción: módulo con una función por consulta para que el SQL no quede desparramado por los controladores. Todas las consultas parametrizadas (`$1`, `$2`, …); nunca concatenar texto del usuario.
  - Aceptación: ninguna consulta concatena input del usuario; una función por consulta.
  - Verificación: `go test ./...`.
  - Archivos: `api/internal/db/*.go`.

- [ ] **Catálogo de vinos (GET)**
  - Descripción: `GET /vinos` con filtros (tipo, cepa, bodega, añada) y paginación; `GET /vinos/{cod}` con detalle: cepas con porcentajes, bodega elaboradora, maridajes y stock total (S9).
  - Aceptación: filtros y paginación funcionan; detalle con composición y maridajes.
  - Verificación: `curl` + tests.
  - Archivos: `api/internal/httpapi/vinos.go`.

- [ ] **CRUD vinos (POST/PUT/DELETE)**
  - Descripción: `POST /vinos` (alta con composición de cepas), `PUT /vinos/{cod}` (modificación; el cambio de precio lo audita el trigger RN-13), `DELETE /vinos/{cod}` (restringido por RN-14 si tiene movimientos).
  - Aceptación: alta/edición/baja correctas; % que no suman 100 llega como 422; borrado con movimientos rechazado.
  - Verificación: tests + `curl`.
  - Archivos: `api/internal/httpapi/vinos.go`.

- [ ] **CRUD clientes**
  - Descripción: `GET/POST/PUT/DELETE /clientes` contemplando los 3 subtipos (socio, distribuidor, exportador) y sus datos propios (zona/habilitación, país destino, permisos). El descuento lo asigna la base (`fn_descuento_cliente`), no la API.
  - Aceptación: alta y lectura de cada subtipo con sus columnas.
  - Verificación: tests + `curl`.
  - Archivos: `api/internal/httpapi/clientes.go`.

- [ ] **Comprobantes**
  - Descripción: `POST /comprobantes` (cabecera + renglones en una sola transacción, invocando las funciones de la base; la API no envía ni calcula precios) y `GET /comprobantes/{nro}`.
  - Aceptación: la venta completa es atómica; vender sin stock devuelve 409 y no deja datos a medias; totales calculados por la base.
  - Verificación: test de venta sin stock → 409.
  - Archivos: `api/internal/httpapi/comprobantes.go`.

- [ ] **Transferencias**
  - Descripción: `POST /transferencias` (alta), `POST /transferencias/{nro}/renglones` (carga mientras está en confección), `POST /transferencias/{nro}/terminar`, `POST /transferencias/{nro}/procesar` (invoca `sp_procesar_transferencia`).
  - Aceptación: circuito completo respetando estados; cambios fuera de confección rechazados.
  - Verificación: tests + `curl`.
  - Archivos: `api/internal/httpapi/transferencias.go`.

- [ ] **Ingresos**
  - Descripción: `POST /ingresos`, `POST /ingresos/{cod}/renglones`, `POST /ingresos/{cod}/procesar` (invoca `sp_procesar_ingreso`). Mismo circuito que transferencias.
  - Aceptación: solo un ingreso terminado impacta el depósito y pasa a procesado.
  - Verificación: tests + `curl`.
  - Archivos: `api/internal/httpapi/ingresos.go`.

- [ ] **Reportes (S1-S12)**
  - Descripción: exponer las consultas S1–S12 como endpoints de solo lectura.
  - Aceptación: reportes devuelven los datos esperados sin efectos colaterales.
  - Verificación: `curl` + tests.
  - Archivos: `api/internal/httpapi/reportes.go`.

- [ ] **Errores SQLSTATE→HTTP**
  - Descripción: manejo central que traduce el SQLSTATE de PostgreSQL a HTTP usando el código `pgconn.PgError`: `23505`→409 (conflicto), `23514`/`23502`→422, `22P02`→400, `40001`/`40P01`→503 (con reintento sugerido). También captura los `RAISE EXCEPTION` de triggers/procedimientos.
  - Aceptación: errores de reglas de negocio llegan con el código correcto y mensaje claro.
  - Verificación: tests que provocan cada tipo de error.
  - Archivos: `api/internal/httperr/`.

- [ ] **Pruebas e inyección SQL**
  - Descripción: ≥8 pruebas automáticas; ≥3 provocan una violación de regla de la base y verifican el código de respuesta (stock insuficiente, cambio de estado inválido, precio negativo). Demostrar una inyección SQL fallida: enviar un valor malicioso a un endpoint con filtro y mostrar que, por estar parametrizado, se trata como texto.
  - Aceptación: `go test ./...` en verde; captura de la inyección fallida para el informe.
  - Verificación: `go test ./...`.
  - Archivos: `api/**/*_test.go`.

- [ ] **Docker Compose y documentación**
  - Descripción: `docker-compose.yml` que levanta base + API con un solo comando; documentación OpenAPI/Swagger o colección Postman coherente con las rutas reales.
  - Aceptación: `docker compose up` funciona; documentación coherente con las rutas.
  - Verificación: `docker compose up`.
  - Archivos: `docker-compose.yml`, `api/docs/`.

---

## Milestone 7 — Etapa 7: Front

> Interfaz Alpine.js con 5 pantallas que consumen la API y muestran los errores de las reglas de negocio, sin lógica de cálculo en el cliente.

- [ ] **Estructura y capa API**
  - Descripción: `front/` con una capa que concentra las llamadas a la API y URL base configurable; bocetos de las 5 pantallas. El front no calcula totales, descuentos ni stock.
  - Aceptación: el front consume únicamente la API; sin lógica de cálculo.
  - Verificación: servir estático local.
  - Archivos: `front/index.html`, `front/js/api.js`.

- [ ] **Catálogo de vinos**
  - Descripción: listado paginado con filtros (tipo, cepa, bodega, añada) y detalle con composición y maridajes (consumiendo `GET /vinos` y `GET /vinos/{cod}`).
  - Aceptación: filtros y paginación contra la API real.
  - Verificación: pantalla funcionando contra la API.
  - Archivos: `front/`.

- [ ] **Alta/edición de vino**
  - Descripción: formulario con composición de cepas; muestra el error del backend cuando los porcentajes no suman 100 (RN-05) tal cual lo devuelve la API, sin reemplazarlo por un mensaje genérico.
  - Aceptación: error de la regla RN-05 visible.
  - Verificación: pantalla contra la API.
  - Archivos: `front/`.

- [ ] **Nueva venta**
  - Descripción: elegir cliente y sala, agregar vinos, ver el total calculado por el backend; mostrar el error de stock insuficiente (RN-09).
  - Aceptación: total viene del backend; venta sin stock muestra el mensaje y no deja datos a medias.
  - Verificación: pantalla contra la API.
  - Archivos: `front/`.

- [ ] **Transferencias**
  - Descripción: crear transferencia, cargar renglones y pasar de estado con botones habilitados según el estado actual (`en_confeccion`/`terminado`/`procesado`).
  - Aceptación: botones habilitados según `estado`; cambios fuera de confección rechazados por la API.
  - Verificación: pantalla contra la API.
  - Archivos: `front/`.

- [ ] **Tablero**
  - Descripción: ranking de los 10 vinos más vendidos (S1), ventas por sala en el último trimestre en gráfico (S8) y vinos sin stock en una sala elegida (S6).
  - Aceptación: los tres bloques funcionan contra la API de reportes.
  - Verificación: pantalla contra la API.
  - Archivos: `front/`.

---

## Milestone 8 — Etapa 8: Nube

> Desplegar el sistema con URL pública HTTPS, seguridad (cifrado, roles con privilegios mínimos, secretos fuera del repo) y backup/restauración probados.

- [ ] **Elección de proveedor**
  - Descripción: comparar ≥2 proveedores (Neon, Supabase, Render, Railway, Fly.io, planes gratuitos de AWS/Azure/GCP o un VPS propio con Docker) y elegir uno; anotar la decisión y los límites vigentes del plan en el informe.
  - Aceptación: decisión y límites documentados.
  - Verificación: decisión en informe.
  - Archivos: `docs/` (informe).

- [ ] **Base en nube**
  - Descripción: crear la base y los 3 roles (propietario, `app_rw`, solo lectura); aplicar `db/migrations/` en orden con el rol propietario; cargar los datos (completos o reducidos según el plan, ≥10k filas justificado si el plan limita).
  - Aceptación: migraciones aplicadas sin errores; consultas de control OK.
  - Verificación: consultas de control en nube.
  - Archivos: `db/migrations/`.

- [ ] **Deploy API**
  - Descripción: configurar la API con variables de entorno y desplegarla; verificar `GET /salud`.
  - Aceptación: `/salud` OK desde la URL pública.
  - Verificación: URL pública.
  - Archivos: `api/`.

- [ ] **Deploy front**
  - Descripción: desplegar el front apuntando a la URL pública de la API; revisar que la API permita ese origen (CORS).
  - Aceptación: front accesible por URL pública HTTPS y consume la API.
  - Verificación: URL pública con HTTPS.
  - Archivos: `front/`.

- [ ] **Seguridad**
  - Descripción: conexión cifrada (`sslmode=require`), puerto de la base no expuesto a internet (restringir por IP o red interna), secretos en variables de entorno del proveedor (nunca en el repo, incluido el historial).
  - Aceptación: conexión no autorizada rechazada; sin secretos en el repo.
  - Verificación: conexión no autorizada rechazada.
  - Archivos: `README.md`, `.env.example`.

- [ ] **Backup y restauración**
  - Descripción: generar backup `pg_dump`, restaurar en una base nueva con `pg_restore`/`psql`, verificar conteos; disparar una regla (venta sin stock) en nube y dejar la captura.
  - Aceptación: backup restaurado con conteos coincidentes; regla comprobada en nube.
  - Verificación: comandos documentados.
  - Archivos: `docs/` (informe).

---

## Milestone 9 — Etapa 9: Documentación y defensa

> Dejar el proyecto reproducible por un tercero (README, informe final, trazabilidad) y preparar la demo en vivo y la defensa oral.

- [ ] **README reproducible**
  - Descripción: README principal con descripción, requisitos, cómo levantar todo en local con Docker Compose, cómo ejecutar migraciones, carga y pruebas, y la URL de la nube.
  - Aceptación: `docker compose up` en una máquina limpia levanta todo.
  - Verificación: `docker compose up`.
  - Archivos: `README.md`.

- [ ] **Informe final**
  - Descripción: juntar los informes parciales según la estructura de la sección 10.2 — introducción, modelo de datos, integridad, carga, índices, consultas, API/front, nube y conclusiones.
  - Aceptación: informe completo y coherente con los entregables.
  - Verificación: informe compilado.
  - Archivos: `docs/` (informe).

- [ ] **Trazabilidad reglas**
  - Descripción: tabla regla → mecanismo → caso de prueba cubriendo RN-01…RN-15 y RI-01…RI-07, junto con la guía de «dónde va cada regla».
  - Aceptación: cada regla con su mecanismo y su prueba referenciada.
  - Verificación: tabla en informe.
  - Archivos: `docs/` (informe).

- [ ] **Demo y defensa oral**
  - Descripción: demo 10–15 min sobre la nube (recorrer el flujo de venta, mostrar el rechazo de una venta sin stock, procesar una transferencia, mostrar una consulta con su plan de ejecución) y defensa oral individual.
  - Aceptación: cada integrante puede explicar y modificar en vivo cualquier parte.
  - Verificación: demo en vivo.
  - Archivos: —.
