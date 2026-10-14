# Implementation Plan: Bodegas del Atuel

> TPI Bases de Datos · Ingeniería en Sistemas · UTN Facultad Regional San Rafael · Ciclo 2026.
> Documento de planificación. Fuentes: `SPEC.md` (síntesis ejecutable), `docs/consignas.md` (enunciado de la cátedra), `docs/resumen_bd.md` (modelo y decisiones) y `docs/entregables/etapa 1/` (lo ya construido). La lista operativa detallada está en `tasks/todo.md`.

---

## 1. Overview

Sistema de gestión y distribución para la empresa vitivinícola ficticia **«Bodegas del Atuel»**: producción de uva y vino, distribución a través de un depósito central (ingresos y transferencias) y venta en una red de salas.

**La capa de datos es el corazón del sistema** y representa el **70 % de la nota** (modelo + constraints + lógica PL/pgSQL + carga + índices + consultas). La **API (Go + chi + pgx)** y el **front (Alpine.js)** son el *medio* para demostrar que la base funciona como parte de un sistema real: exponen la base **sin ocultar el SQL** y **sin duplicar las reglas** que ya viven en ella.

> **Regla de oro:** la API no recalcula totales, descuentos ni stock. Llama a las funciones/procedimientos de la base y deja que los triggers protejan las reglas.

El trabajo se entrega en **9 etapas** con dependencias en cadena. Cada etapa es un **milestone**; cada milestone se descompone en **issues** verificables. **La Etapa 1 ya está completa.**

```
1 Modelado ✓ → 2 Integridad → 3 Carga → 4 Índices → 5 Consultas
                                    ↓
8 Nube ← 7 Front ← 6 API ←──────────┘
   ↓
9 Documentación y defensa
```

**Peso en la rúbrica (100 pts):** Modelado 15 · Constraints 8 · Lógica 17 · Carga 8 · Índices 10 · Consultas 12 · API 10 · Front 5 · Nube 10 · Docs/Git/demo 5.

---

## 2. Contexto del dominio (base del plan)

### 2.1 Modelo de datos (31 tablas, ya definido en Etapa 1)

- **Ubicación/personal:** `departamento`, `localidad`, `deposito`, `sala_venta`, `empleado`.
- **Producción:** `finca`, `parcela` (débil), `cepa`, `lote_uva`, `analisis_calidad`.
- **Bodegas/vinos:** `bodega`, `vino`, `composicion`, `maridaje`, `vino_maridaje`, `auditoria_precio`.
- **Clientes/ventas:** `cliente` (supertipo) + `socio`/`distribuidor`/`exportador` (subtipos), `permiso_exportacion`, `comprobante`, `renglon_comprobante`.
- **Logística/stock:** `transportista`, `transportista_localidad`, `ingreso`, `renglon_ingreso`, `transferencia`, `renglon_transferencia`, `stock_sala`, `stock_deposito`.

37 claves foráneas. Ciclo `localidad → empleado → sala_venta → localidad` resuelto con FK `DEFERRABLE INITIALLY DEFERRED` en `localidad.cuit_encargado`.

### 2.2 Reglas de negocio a proteger en la base

- **Explícitas RN-01…RN-15:** precio único >0; sala/localidad/encargado; empleado en una sala; cosecha única por parcela/campaña; cortes suman 100; descuento por tipo (10/20/30 %); permisos con vencimiento>emisión; total del comprobante calculado; no vender sin stock (stock ≥0); transiciones de estado sin retroceso (ingreso/transferencia); renglones bloqueados fuera de confección; fecha de confección inmutable; auditoría de precio; no borrar con movimientos; valores positivos y graduación 5–20.
- **Implícitas RI-01…RI-07:** encargado en sala de su localidad; todo vino con ≥1 maridaje; precio unitario como copia histórica; vinos del ingreso de la bodega de origen; transportista cubre la localidad del depósito; exportador con >3 permisos → 35 %; subtipo coincide con `tipo`.

Cada regla necesita **mecanismo en la base** (constraint/función/procedimiento/trigger) y **al menos un caso de prueba** en `db/tests/db_tests.sql`. La tabla de trazabilidad regla→mecanismo→prueba se cierra en la etapa 9.

### 2.3 Consultas SQL a resolver (etapa 5)

- **UPDATE (U1–U6):** recalcular totales; +20 % salario a >5 años; +13 % precio a una bodega; lunes↔miércoles en una sentencia; −15 % a los 10 menos vendidos; exportadores con >3 permisos → 35 %.
- **INSERT (I1–I6):** cobertura transportista-localidad (General Alvear); maridaje «cordero al disco» si hay tinto ≥14°; comprobante de 3 renglones en sala 1; nueva bodega; nueva sala; ingreso en confección de 120 botellas.
- **DELETE (D1–D6):** comprobantes >5 años de socios; cepas sin uso; empleados de sala dada de baja con <2 años; socios sin compras >5 años; ingresos procesados >365 días; socios sin compras de una localidad.
- **SELECT (S1–S8):** top 10 vinos; división relacional (vendidos en todas las salas); clientes por tipo en la última semana; top 5 salas por transferencias de un vino; salas con menos pendientes; vinos sin stock en sala pero con stock en depósito; transportista más activo; ventas por sala en el trimestre.
- **Avanzadas (S9–S12):** ficha de vino; rendimiento kg/ha con CTE correlacionada; `RANK() OVER (PARTITION BY …)` + acumulado; `NOT EXISTS`/anti-join.

### 2.4 API (etapa 6)

Endpoints: `GET /salud`; vinos (`GET /vinos`, `GET /vinos/{cod}`, `POST/PUT/DELETE`); clientes (CRUD, 3 subtipos); comprobantes (`POST /comprobantes`, `GET /comprobantes/{nro}`); transferencias (`POST /transferencias`, `/{nro}/renglones`, `/{nro}/terminar`, `/{nro}/procesar`); ingresos (`POST /ingresos`, `/{cod}/renglones`, `/{cod}/procesar`); reportes S1–S12 (solo lectura).

Traducción de errores SQLSTATE→HTTP: `23505`→409 · `23514`/`23502`→422 · `22P02`→400 · `40001`/`40P01`→503.

### 2.5 Volúmenes de carga (etapa 3)

Catálogos reales 10–60 filas; salas/fincas/empleados 15–150; parcelas/vinos 300–1000; ingresos/transferencias/stock 500–5000; renglones/lotes/análisis 3k–15k; clientes 20 000; comprobantes 150 000; **renglones de comprobante ≥ 500 000**.

---

## 3. Architecture Decisions

| Decisión | Elección | Justificación |
|---|---|---|
| Motor BD | PostgreSQL 14+ | Requisito; sin ORM/query builders, SQL a mano. |
| Modelo | 31 tablas, 3FN | Entidad débil `parcela`; jerarquía cliente = **supertipo + tabla por subtipo** (evita NULL, permite FK simple en `comprobante` y `permiso_exportacion`; disjunción por FK compuesta `(id_cliente, tipo)`). |
| Claves | Subrogadas salvo CUIT natural (bodega/empleado) | CUIT estable/único/validable con DOMAIN `cuit`; resto IDENTITY compacto. |
| Tipos | `NUMERIC` para dinero/porcentajes; `DATE`/`TIMESTAMPTZ`; ENUM para estados/tipos/día | Nunca `FLOAT`; estados no son texto libre. |
| Reglas | En la base (constraints + funciones + procedimientos + triggers) | Valen aunque alguien acceda directo a la BD; API/front no recalculan. |
| API | Go + `chi` + `pgx` (pool) | Driver nativo, consultas parametrizadas, una función por consulta en la capa de datos. |
| Front | HTML/CSS/JS + Alpine.js (CDN) | Consume solo la API; sin lógica de cálculo. Servidor de estáticos pendiente (ver §7). |
| Carga | Python + psycopg + Faker + random, semilla fija | Reproducible; catálogos reales desde CSV. |
| Roles | propietario / app_rw / solo lectura | La API usa app_rw, nunca propietario. |
| Migraciones | `db/migrations/001…008.sql`, en orden | `001` ya entregado (Etapa 1); cada archivo corre sobre base vacía. |

---

## 4. Task List (por milestone)

> Índice. Cada item mapea a un issue del milestone homónimo; la especificación completa (descripción, aceptación, verificación, archivos) está en `tasks/todo.md`.

### Milestone 1 — Etapa 1: Modelado ✓ (COMPLETA)
La etapa 1 se centra en la documentación inicial: pasar del escenario escrito a un esquema físico en PostgreSQL, recorriendo el DER, el esquema relacional, la normalización 3FN, el diccionario de datos y el DDL base (`001_esquema.sql`).
- [x] DER completo
- [x] Esquema relacional
- [x] Normalización 3FN
- [x] Decisiones de diseño
- [x] Diccionario de datos
- [x] 001_esquema.sql

### Milestone 2 — Etapa 2: Integridad y lógica
Etapa de mayor peso: que las reglas de negocio (RN-01…15 y RI-01…07) vivan dentro de la base mediante constraints, funciones, procedimientos, triggers, vistas y roles, con pruebas y una demo de concurrencia.
- [ ] 002_constraints.sql
- [ ] 003_funciones.sql
- [ ] 004_procedimientos.sql
- [ ] 005_triggers.sql
- [ ] 006_vistas.sql
- [ ] 007_roles.sql
- [ ] db_tests.sql
- [ ] Demo de concurrencia

### Milestone 3 — Etapa 3: Carga masiva
Generar datos coherentes y reproducibles a gran escala (≥100k filas en una tabla) con Python + Faker + semilla fija, catálogos reales en CSV y consultas de control.
- [ ] Catálogos CSV
- [ ] Script de carga Python
- [ ] Coherencia y triggers en carga
- [ ] Carga eficiente por lotes
- [ ] Consultas de control y dump

### Milestone 4 — Etapa 4: Índices
Diseñar índices con evidencia medida (`EXPLAIN ANALYZE, BUFFERS`), comparando antes/después y documentando el costo de escritura.
- [ ] Medición baseline
- [ ] 008_indices.sql
- [ ] Comparativa y costo de escritura

### Milestone 5 — Etapa 5: Consultas SQL
Resolver en SQL las operaciones de inserción, modificación, borrado y consulta (U1–U6, I1–I6, D1–D6, S1–S12), probadas en transacción sobre la base cargada.
- [ ] consultas/update.sql
- [ ] consultas/insert.sql
- [ ] consultas/delete.sql
- [ ] consultas/select.sql

### Milestone 6 — Etapa 6: API REST
Exponer la base mediante una API en Go (chi + pgx) sin ocultar el SQL, con capa de acceso a datos, traducción de errores SQLSTATE→HTTP y pruebas automáticas.
- [ ] Estructura del proyecto Go
- [ ] Conexión y /salud
- [ ] Capa de acceso a datos
- [ ] Catálogo de vinos (GET)
- [ ] CRUD vinos (POST/PUT/DELETE)
- [ ] CRUD clientes
- [ ] Comprobantes
- [ ] Transferencias
- [ ] Ingresos
- [ ] Reportes (S1-S12)
- [ ] Errores SQLSTATE→HTTP
- [ ] Pruebas e inyección SQL
- [ ] Docker Compose y documentación

### Milestone 7 — Etapa 7: Front
Interfaz Alpine.js con 5 pantallas que consumen la API y muestran los errores de las reglas de negocio, sin lógica de cálculo en el cliente.
- [ ] Estructura y capa API
- [ ] Catálogo de vinos
- [ ] Alta/edición de vino
- [ ] Nueva venta
- [ ] Transferencias
- [ ] Tablero

### Milestone 8 — Etapa 8: Nube
Desplegar el sistema con URL pública HTTPS, seguridad (cifrado, roles con privilegios mínimos, secretos fuera del repo) y backup/restauración probados.
- [ ] Elección de proveedor
- [ ] Base en nube
- [ ] Deploy API
- [ ] Deploy front
- [ ] Seguridad
- [ ] Backup y restauración

### Milestone 9 — Etapa 9: Documentación y defensa
Dejar el proyecto reproducible por un tercero (README, informe final, trazabilidad) y preparar la demo en vivo y la defensa oral.
- [ ] README reproducible
- [ ] Informe final
- [ ] Trazabilidad reglas
- [ ] Demo y defensa oral

---

## 5. Checkpoints

- **Tras M1:** base se crea desde cero sin errores. ✓
- **Tras M2:** cada regla RN/RI tiene mecanismo y caso de prueba; demo de concurrencia; la API puede conectarse con un rol no-propietario.
- **Tras M3:** dos ejecuciones con la misma semilla producen los mismos datos; consultas de control sin inconsistencias; ≥100k filas en una tabla.
- **Tras M4:** ≥3 consultas más rápidas con índice; costo de escritura documentado.
- **Tras M5:** U1–U6 / I1–I6 / D1–D6 / S1–S12 resueltas y probadas en transacción.
- **Tras M6:** `docker compose up` levanta base + API; ≥8 tests (≥3 de reglas); intento de venta sin stock devuelve 409.
- **Tras M7:** 5 pantallas contra la API; errores de reglas visibles; sin lógica de cálculo en el cliente.
- **Tras M8:** URL pública HTTPS; conexión cifrada; backup restaurado; una regla disparada en nube.
- **Tras M9:** README reproducible; informe; demo en vivo.

---

## 6. Risks and Mitigations

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Ciclo FK `localidad→empleado→sala→localidad` impide cargar datos | Alto | `localidad.cuit_encargado` DEFERRABLE INITIALLY DEFERRED (ya en `001`). |
| Carga histórica choca con triggers | Medio | `ALTER TABLE … DISABLE TRIGGER` durante la carga, re-habilitar y validar con consultas de control (documentar la decisión y sus riesgos). |
| Sobreventa por concurrencia (última botella) | Alto | `SELECT … FOR UPDATE` en ventas y en `sp_procesar_*`; demo con dos sesiones `psql`. |
| Secretos (contraseñas, cadenas de conexión) en el repo | Alto | Variables de entorno + `.env.example` sin secretos; revisar historial de Git antes de entregar. |
| `CURRENT_DATE` dentro de `CHECK` | Medio | Prohibido; las reglas que dependen de la fecha actual van en trigger (rompen backup si están en CHECK). |
| Regla de oro violada (recalcular totales/stock en API o front) | Alto | Revisión en PR; tests que provocan errores de reglas; la API solo invoca funciones/procedimientos. |
| Volúmenes de carga insuficientes o lentos | Medio | Medir conteos por tabla; carga por lotes/COPY con tiempos registrados; apuntar a ≥500k renglones. |
| `sp_procesar_*` con vino sin fila en stock no descuenta nada | Medio | Verificar existencia y suficiencia antes de descontar (nota del Anexo A.6 de consignas). |
| Plan gratuito de nube limita almacenamiento | Medio | Carga reducida (≥10k filas en una tabla) justificada; volumen completo en local. |

---

## 7. Open Questions

1. **Servido del front:** ¿nginx (contenedor propio) o lo sirve la API? (abierto).
2. **Versión de Go** exacta a fijar en `go.mod` y el Dockerfile.
3. **Proveedor cloud** y plan (Neon / Render / Railway / Fly.io, etc.) — verificar límites vigentes.
4. **Integrantes y roles** rotativos por etapa (Datos / API / Front-Integración / Infraestructura).
5. **Herramienta de modelado** (draw.io / dbdiagram / pgModeler).

Resueltas: router = `chi`; jerarquía de clientes = supertipo + tabla por subtipo.

---

## 8. Tracking

Se planeó el seguimiento en GitHub (milestones + issues del repo `JoseM656/atuel-management-bd`), pero **se requiere revisión y aprobación de este plan antes de crear los issues**. La lista operativa de tareas vive en `tasks/todo.md`.
